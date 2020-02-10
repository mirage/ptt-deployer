open Common
module Github = Current_github
module Git = Current_git
module E = Current_albatross_deployer
open Current.Syntax

let daily = Current_cache.Schedule.v ~valid_for:(Duration.of_day 1) ()

let v ~ip_relay ~cert_fingerprint_relay =
  let cert_key = Certificate.generate 32 in
  let cert_der, _cert_fingerprint =
    Result.get_ok (Certificate.v "ocaml.ci.dev" cert_key)
  in
  let repo_ptt =
    Github.(
      Api.Anonymous.head_of
        { Repo_id.owner = "dinosaure"; name = "ptt" }
        (`Ref "refs/heads/master"))
    |> Git.fetch
  in
  let config =
    collapse ~key:"config" ~value:"spam_filter" ~label:"Spam filter"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.spamfilter";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --domain ocaml.ci.dev \
                  --postmaster hostmaster@ocaml.ci.dev";
               ];
           }
           repo_ptt
         |> E.Unikernel.of_docker ~location:(Fpath.v "/unikernel.hvt")
       and+ ip_relay = ip_relay in
       {
         E.Config.Pre.service = "ptt-spamfilter";
         unikernel;
         args =
           (fun ip ->
             [
               Fmt.str "--cert-fingerprint=osau.re:SHA256:%s"
                 cert_fingerprint_relay;
               Fmt.str "--cert-key=%s" cert_key;
               Fmt.str "--cert-der=%s" cert_der;
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--destination";
               Ipaddr.V4.to_string ip_relay;
             ]);
         memory = 512;
         network = "br1";
       }
  in
  let ip = get_ip config in
  [ ("ptt-spamfilter", config, ip, [ { E.Port.source = 25; target = 25 } ]) ]
