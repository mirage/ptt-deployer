open Current.Syntax
open Common
module Github = Current_github
module Git = Current_git
module E = Current_albatross_deployer
open Config

let v ~ip_dns_resolver ~ip_dns_primary_git =
  let cert_key_relay = Certificate.generate 32 in
  let cert_key_signer = Certificate.generate 32 in
  let cert_der_relay, cert_fingerprint_relay =
    Result.get_ok (Certificate.v smtp_domain cert_key_relay)
  in
  let cert_der_signer, cert_fingerprint_signer =
    Result.get_ok (Certificate.v smtp_domain cert_key_signer)
  in
  let repo_ptt =
    Github.(
      Api.Anonymous.head_of
        { Repo_id.owner = "dinosaure"; name = "ptt" }
        (`Ref "refs/heads/master"))
    |> Git.fetch
  in
  let config_relay =
    collapse ~key:"config" ~value:"dns_relay" ~label:"PTT relay"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.relay";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --remote \
                  git@10.0.0.1:relay.git --ssh-key=" ^ ssh_key
                 ^ " --domain " ^ smtp_domain ^ " --postmaster hostmaster@"
                 ^ smtp_domain;
               ];
           }
           repo_ptt
         |> E.Unikernel.of_docker ~location:(Fpath.v "/unikernel.hvt")
       and+ ip_dns_resolver = ip_dns_resolver in
       {
         E.Config.Pre.service = "ptt-relay";
         unikernel;
         args =
           (fun ip ->
             [
               Fmt.str "--cert-key=%s" cert_key_relay;
               Fmt.str "--cert-der=%s" cert_der_relay;
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--resolver";
               "tcp://" ^ Ipaddr.V4.to_string ip_dns_resolver;
             ]);
         memory = 512;
         network = "br0";
       }
  in
  let ip_relay = get_ip config_relay in
  let config_signer =
    collapse ~key:"config" ~value:"dns_signer" ~label:"PTT signer"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.signer";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --dns-key="
                 ^ dns_personal_key ^ " --selector ptt --domain " ^ smtp_domain
                 ^ " --private-key=" ^ dkim_key ^ " --postmaster hostmaster@"
                 ^ smtp_domain;
               ];
           }
           repo_ptt
         |> E.Unikernel.of_docker ~location:(Fpath.v "/unikernel.hvt")
       and+ ip_dns_primary_git = ip_dns_primary_git
       and+ ip_relay = ip_relay in
       {
         E.Config.Pre.service = "ptt-signer";
         unikernel;
         args =
           (fun ip ->
             [
               Fmt.str "--cert-fingerprint=%s:SHA256:%s" smtp_domain
                 cert_fingerprint_relay;
               Fmt.str "--cert-key=%s" cert_key_signer;
               Fmt.str "--cert-der=%s" cert_der_signer;
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--dns-server=" ^ Ipaddr.V4.to_string ip_dns_primary_git;
               "--destination=" ^ Ipaddr.V4.to_string ip_relay;
             ]);
         memory = 512;
         network = "br0";
       }
  in
  let ip_signer = get_ip config_signer in
  let config_submission =
    collapse ~key:"config" ~value:"dns_submission" ~label:"PTT submission"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.submission";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --remote \
                  git@10.0.0.1:relay.git --ssh-key=" ^ ssh_key ^ " --domain "
                 ^ smtp_domain ^ " --hostname " ^ smtp_domain ^ " --dns-key="
                 ^ dns_personal_key ^ " --postmaster hostmaster@" ^ smtp_domain;
               ];
           }
           repo_ptt
         |> E.Unikernel.of_docker ~location:(Fpath.v "/unikernel.hvt")
       and+ ip_dns_primary_git = ip_dns_primary_git
       and+ ip_signer = ip_signer in
       {
         E.Config.Pre.service = "ptt-submission";
         unikernel;
         args =
           (fun ip ->
             [
               Fmt.str "--cert-fingerprint=%s:SHA256:%s" smtp_domain
                 cert_fingerprint_signer;
               "--dns-server=" ^ Ipaddr.V4.to_string ip_dns_primary_git;
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--destination=" ^ Ipaddr.V4.to_string ip_signer;
             ]);
         memory = 512;
         network = "br0";
       }
  in
  let ip_submission = get_ip config_submission in

  [
    ("ptt-relay", config_relay, ip_relay, []);
    ("ptt-signer", config_signer, ip_signer, []);
    ( "ptt-submission",
      config_submission,
      ip_submission,
      [ { E.Port.source = 465; target = 465 } ] );
  ]
  @ Reception.v ~ip_dns_resolver ~ip_dns_primary_git ~ip_relay
      ~cert_fingerprint_relay
