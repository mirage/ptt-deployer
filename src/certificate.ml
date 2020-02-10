open Rresult

let prefix =
  X509.Distinguished_name.[ Relative_distinguished_name.singleton (CN "PTT") ]

let cacert_dn =
  X509.Distinguished_name.(
    prefix
    @ [ Relative_distinguished_name.singleton (CN "Ephemeral CA for PTT") ])

let cacert_lifetime = Ptime.Span.v (365, 0L)
let cacert_serial_number = Z.zero

let v domain_name seed =
  Domain_name.of_string domain_name >>= Domain_name.host >>= fun domain_name ->
  let private_key =
    let seed = Cstruct.of_string (Base64.decode_exn ~pad:false seed) in
    let g = Mirage_crypto_rng.(create ~seed (module Fortuna)) in
    Mirage_crypto_pk.Rsa.generate ~g ~bits:2048 ()
  in
  let valid_from = Ptime.v (Ptime_clock.now_d_ps ()) in
  Ptime.add_span valid_from cacert_lifetime
  |> Option.to_result ~none:(R.msgf "End time out of range")
  >>= fun valid_until ->
  X509.Signing_request.create cacert_dn (`RSA private_key) >>= fun ca_csr ->
  let extensions =
    let open X509.Extension in
    let key_id =
      X509.Public_key.id X509.Signing_request.((info ca_csr).public_key)
    in
    let authority_key_id =
      ( Some key_id,
        X509.General_name.(singleton Directory [ cacert_dn ]),
        Some cacert_serial_number )
    in
    empty
    |> add Subject_alt_name
         ( true,
           X509.General_name.(
             singleton DNS [ Domain_name.to_string domain_name ]) )
    |> add Basic_constraints (true, (false, None))
    |> add Key_usage
         (true, [ `Digital_signature; `Content_commitment; `Key_encipherment ])
    |> add Subject_key_id (false, key_id)
    |> add Authority_key_id (false, authority_key_id)
  in
  X509.Signing_request.sign ~valid_from ~valid_until ~extensions
    ~serial:cacert_serial_number ca_csr (`RSA private_key) cacert_dn
  |> R.reword_error (R.msgf "%a" X509.Validation.pp_signature_error)
  >>= fun certificate ->
  let fingerprint = X509.Certificate.fingerprint `SHA256 certificate in
  Ok
    ( Base64.encode_string
        (Cstruct.to_string (X509.Certificate.encode_der certificate)),
      Base64.encode_string (Cstruct.to_string fingerprint) )

let generate len =
  let res = Bytes.create len in
  for _ = 0 to len - 1 do
    Bytes.set res 0 (Char.unsafe_chr (Random.bits () land 0xff))
  done;
  Base64.encode_string (Bytes.unsafe_to_string res)
