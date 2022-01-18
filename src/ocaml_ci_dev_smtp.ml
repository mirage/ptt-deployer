open Current.Syntax
open Common
module Github = Current_github
module Git = Current_git
module E = Current_albatross_deployer

let ocaml_ci_dev = "ocaml.ci.dev"

let v ~ip_dns_resolver ~ip_dns_primary_git =
  let cert_key_relay = Certificate.generate 32 in
  let cert_key_signer = Certificate.generate 32 in
  let cert_der_relay, cert_fingerprint_relay =
    Result.get_ok (Certificate.v ocaml_ci_dev cert_key_relay)
  in
  let cert_der_signer, cert_fingerprint_signer =
    Result.get_ok (Certificate.v ocaml_ci_dev cert_key_signer)
  in
  let repo_ptt =
    Github.(
      Api.Anonymous.head_of
        { Repo_id.owner = "dinosaure"; name = "ptt" }
        (`Ref "refs/heads/master"))
    |> Git.fetch
  in
  let config_ptt_relay =
    collapse ~key:"config" ~value:"dns_ptt_relay" ~label:"PTT relay"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.relay";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --remote \
                  git@10.0.0.1:relay.git --ssh-key \
                  rsa:gFTbNbVSAOLaQFs93nWtXDPBvvM6muWyruORR532 --domain \
                  ocaml.ci.dev --postmaster hostmaster@ocaml.ci.dev";
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
         network = "br1";
       }
  in
  let ip_ptt_relay = get_ip config_ptt_relay in
  let config_ptt_signer =
    collapse ~key:"config" ~value:"dns_ptt_signer" ~label:"PTT signer"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.signer";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 \
                  --dns-key=personal._update.ocaml.ci.dev:SHA256:n3ZU6y20DsOmpqGL9TpPTtVW89EX+mb0fG+0x6N+C0I= \
                  --selector ptt --domain ocaml.ci.dev \
                  --private-key=tPIv8iEGGl1BBUgzdsWv1eJV6nd8vIuHiG0ccsNYdxs= \
                  --postmaster hostmaster@ocaml.ci.dev";
               ];
           }
           repo_ptt
         |> E.Unikernel.of_docker ~location:(Fpath.v "/unikernel.hvt")
       and+ ip_dns_primary_git = ip_dns_primary_git
       and+ ip_ptt_relay = ip_ptt_relay in
       {
         E.Config.Pre.service = "ptt-signer";
         unikernel;
         args =
           (fun ip ->
             [
               Fmt.str "--cert-fingerprint=osau.re:SHA256:%s"
                 cert_fingerprint_relay;
               Fmt.str "--cert-key=%s" cert_key_signer;
               Fmt.str "--cert-der=%s" cert_der_signer;
               "-l debug";
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--dns-server=" ^ Ipaddr.V4.to_string ip_dns_primary_git;
               "--destination=" ^ Ipaddr.V4.to_string ip_ptt_relay;
             ]);
         memory = 512;
         network = "br1";
       }
  in
  let ip_ptt_signer = get_ip config_ptt_signer in
  let config_ptt_submission =
    collapse ~key:"config" ~value:"dns_ptt_submission" ~label:"PTT submission"
    @@ let+ unikernel =
         Docker.build_image
           {
             Docker.dockerfile = "Dockerfile.submission";
             args =
               [
                 "TARGET=hvt";
                 "EXTRA_FLAGS=--ipv4-gateway=10.0.0.1 --remote \
                  git@10.0.0.1:relay.git --ssh-key \
                  rsa:gFTbNbVSAOLaQFs93nWtXDPBvvM6muWyruORR532 --domain \
                  ocaml.ci.dev --hostname smtp.ocaml.ci.dev \
                  --dns-key=personal._update.ocaml.ci.dev:SHA256:n3ZU6y20DsOmpqGL9TpPTtVW89EX+mb0fG+0x6N+C0I= \
                  --postmaster hostmaster@ocaml.ci.dev";
               ];
           }
           repo_ptt
         |> E.Unikernel.of_docker ~location:(Fpath.v "/unikernel.hvt")
       and+ ip_dns_primary_git = ip_dns_primary_git
       and+ ip_ptt_signer = ip_ptt_signer in
       {
         E.Config.Pre.service = "ptt-submission";
         unikernel;
         args =
           (fun ip ->
             [
               Fmt.str "--cert-fingerprint=osau.re:SHA256:%s"
                 cert_fingerprint_signer;
               "--dns-server=" ^ Ipaddr.V4.to_string ip_dns_primary_git;
               "--ipv4=" ^ Ipaddr.V4.to_string ip ^ "/24";
               "--destination=" ^ Ipaddr.V4.to_string ip_ptt_signer;
               "-l";
               "debug";
             ]);
         memory = 512;
         network = "br1";
       }
  in
  let ip_ptt_submission = get_ip config_ptt_submission in

  [
    ("ptt-relay", config_ptt_relay, ip_ptt_relay, []);
    ("ptt-signer", config_ptt_signer, ip_ptt_signer, []);
    ( "ptt-submission",
      config_ptt_submission,
      ip_ptt_submission,
      [ { E.Port.source = 465; target = 465 } ] );
  ]
  @ Spam_filter.v ~ip_relay:ip_ptt_relay ~cert_fingerprint_relay
