open Common
module Github = Current_github
module Git = Current_git
module E = Current_albatross_deployer
open Current.Syntax
open Config

let daily = Current_cache.Schedule.v ~valid_for:(Duration.of_day 1) ()

let v ~ip_dns_resolver ~ip_dns_primary_git ~ip_relay ~cert_fingerprint_relay =
  let cert_key_spamfilter = Certificate.generate 32 in
  let cert_der_spamfilter, cert_fingerprint_spamfilter =
    Result.get_ok (Certificate.v smtp_domain cert_key_spamfilter)
  in
  let repo_ptt =
    Github.(
      Api.Anonymous.head_of
        { Repo_id.owner = "dinosaure"; name = "ptt" }
        (`Ref "refs/heads/master"))
    |> Git.fetch
  in
  let config_spamfilter =
    collapse ~key:"config" ~value:"spamfilter" ~label:"Spam filter"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.spamfilter";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --domain " ^ smtp_domain
                 ^ " --postmaster hostmaster@" ^ smtp_domain;
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
               Fmt.str "--cert-fingerprint=%s:SHA256:%s" smtp_domain
                 cert_fingerprint_relay;
               Fmt.str "--cert-key=%s" cert_key_spamfilter;
               Fmt.str "--cert-der=%s" cert_der_spamfilter;
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--destination";
               Ipaddr.V4.to_string ip_relay;
             ]);
         memory = 512;
         network = "br1";
       }
  in
  let ip_spamfilter = get_ip config_spamfilter in
  let config_verifier =
    collapse ~key:"config" ~value:"verifier" ~label:"PTT verifier"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.verifier";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --domain " ^ smtp_domain
                 ^ " --hostname " ^ smtp_domain ^ " --dns-key="
                 ^ dns_personal_key ^ " --postmaster hostmaster@" ^ smtp_domain;
               ];
           }
           repo_ptt
         |> E.Unikernel.of_docker ~location:(Fpath.v "/unikernel.hvt")
       and+ ip_dns_primary_git = ip_dns_primary_git
       and+ ip_dns_resolver = ip_dns_resolver
       and+ ip_spamfilter = ip_spamfilter in
       {
         E.Config.Pre.service = "ptt-spamfilter";
         unikernel;
         args =
           (fun ip ->
             [
               Fmt.str "--cert-fingerprint=%s:SHA256:%s" smtp_domain
                 cert_fingerprint_spamfilter;
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--dns-server=" ^ Ipaddr.V4.to_string ip_dns_primary_git;
               "--resolver=" ^ Ipaddr.V4.to_string ip_dns_resolver;
               "--destination";
               Ipaddr.V4.to_string ip_spamfilter;
             ]);
         memory = 512;
         network = "br1";
       }
  in
  let ip_verifier = get_ip config_verifier in
  [
    ("ptt-spamfilter", config_spamfilter, ip_spamfilter, []);
    ( "ptt-verifier",
      config_verifier,
      ip_verifier,
      [ { E.Port.source = 25; target = 25 } ] );
  ]
