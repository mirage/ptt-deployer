module Github = Current_github
module Git = Current_git
module R = Rresult.R
module Build_docker = Build.Make (Docker)
open Config

let docker dockerfile ~name ~git targets =
  let build_info = { Docker.dockerfile; args = [] } in
  let deploys =
    targets |> List.map (fun (branch, service) -> (branch, { Docker.service }))
  in
  (build_info, deploys, git, name)

(* UNIKERNELS *)
open Current.Syntax
open Common
module E = Current_albatross_deployer

(* DNS PRIMARY GIT *)

let daily = Current_cache.Schedule.v ~valid_for:(Duration.of_day 1) ()

let config_dns_primary_git =
  collapse ~key:"config" ~value:"dns_primary_git" ~label:"DNS primary git"
  @@ let+ unikernel =
       let repo =
         Git.clone ~schedule:daily ~gref:"main"
           "https://github.com/roburio/dns-primary-git.git"
       in
       E.Unikernel.of_git ~mirage_version:`Mirage_3
         ~config_file:(Current.return (Fpath.v "config.ml"))
         ~args:
           (Current.return
              [
                "--ipv4-gateway=10.0.0.1";
                "--axfr";
                "--remote=git@10.0.0.1:zone.git";
                "--ssh-key=" ^ ssh_key;
              ])
         repo
     in
     {
       E.Config.Pre.service = "dns-primary-git";
       unikernel;
       args =
         (fun ip -> [ "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24"; "--axfr" ]);
       memory = 256;
       network = "br0";
     }

let ip_dns_primary_git = get_ip config_dns_primary_git

(* DNS LETSENCRYPT SECONDARY *)

let config_dns_letsencrypt_secondary ~ip_dns_primary_git =
  collapse ~key:"config" ~value:"dns_letsencrypt_secondary"
    ~label:"DNS Let's encrypt secondary"
  @@ let+ unikernel =
       let repo =
         Git.clone ~schedule:daily ~gref:"main"
           "https://github.com/roburio/dns-letsencrypt-secondary.git"
       in
       E.Unikernel.of_git ~mirage_version:`Mirage_3
         ~config_file:(Current.return (Fpath.v "config.ml"))
         ~args:
           (Current.return
              [
                "--ipv4-gateway=10.0.0.1";
                "--dns-key=" ^ dns_personal_key;
                "--account-key-seed=" ^ letsencrypt_account_key;
                "--email=postmaster@" ^ smtp_domain;
              ])
         repo
     and+ ip_dns_primary_git = ip_dns_primary_git in
     {
       E.Config.Pre.service = "dns-le";
       unikernel;
       args =
         (fun ip ->
           [
             "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
             "--dns-server=" ^ Ipaddr.V4.to_string ip_dns_primary_git;
           ]);
       memory = 256;
       network = "br0";
     }

(* DNS RESOLVER *)

let config_dns_resolver =
  collapse ~key:"config" ~value:"resolver" ~label:"DNS resolver"
  @@ let+ unikernel =
       let repo =
         Git.clone ~schedule:daily ~gref:"master"
           "https://github.com/mirage/dns-resolver.git"
       in
       E.Unikernel.of_git ~mirage_version:`Mirage_3
         ~config_file:(Current.return (Fpath.v "config.ml"))
         ~args:(Current.return [ "--ipv4-gateway=10.0.0.1" ])
         repo
     in
     {
       E.Config.Pre.service = "dns-resolver";
       unikernel;
       args = (fun ip -> [ "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24" ]);
       memory = 256;
       network = "br0";
     }

let ip_dns_resolver = get_ip config_dns_resolver

(* EMAIL STACK *)

let git_local_bare path = Current_git.Local.v ~bare:true (Fpath.v path)

let v () =
  let docker_services =
    let build (build_info, deploys, git, name) =
      Build_docker.repo ~git ~name [ (build_info, deploys) ]
    in
    Current.all
    @@ List.map build
         [
           docker "Dockerfile" ~name:"ptt-deployer"
             ~git:(`Local (git_local_bare "/git/ptt-deployer.git"))
             [ ("live", "infra_ptt-deployer") ];
         ]
  in

  let mirage_unikernels =
    let open Current.Syntax in
    let module E = Current_albatross_deployer in
    let config_dns_letsencrypt_secondary =
      config_dns_letsencrypt_secondary ~ip_dns_primary_git
    in
    let ip_dns_letsencrypt_secondary =
      get_ip config_dns_letsencrypt_secondary
    in

    let unikernels_to_deploy =
      [
        ( "dns-primary-git",
          config_dns_primary_git,
          ip_dns_primary_git,
          [ { E.Port.source = 53; target = 53 } ] );
        ("dns-resolver", config_dns_resolver, ip_dns_resolver, []);
        ( "dns-letsencrypt-secondary",
          config_dns_letsencrypt_secondary,
          ip_dns_letsencrypt_secondary,
          [] );
      ]
      @ SMTP.v ~ip_dns_resolver ~ip_dns_primary_git
    in
    let _published, monitors =
      unikernels_to_deploy
      |> List.map (fun (label, config, ip, ports) ->
             let config =
               let+ config = config and+ ip = ip in
               E.Config.v config ip
             in
             let deployment = E.deploy_albatross ~label config in
             let publish = E.publish ~service:label ~ports deployment in
             let monitor = E.monitor deployment in
             (publish, E.is_running monitor))
      |> List.split
    in
    Current.all [ Current.all monitors ]
  in
  Current.all [ mirage_unikernels; docker_services ]
