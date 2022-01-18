open Lwt.Infix
open Current.Syntax
module Raw = Current_docker.Raw

let with_tmp ~prefix ~suffix fn =
  let tmp_path = Filename.temp_file prefix suffix in
  Lwt.finalize
    (fun () -> fn tmp_path)
    (fun () ->
      Unix.unlink tmp_path;
      Lwt.return_unit)

let ( >>!= ) = Lwt_result.bind

module Op = struct
  type t = No_context

  let id = "mirage-deploy"

  module Key = struct
    type t = { name : string } [@@deriving to_yojson]

    let digest t = Yojson.Safe.to_string (to_yojson t)
  end

  module Value = struct
    type t = { image : Raw.Image.t; args : string list }

    let digest { image; args } =
      Raw.Image.digest image ^ ":" ^ String.concat " " args
      |> Digest.string |> Digest.to_hex
  end

  module Outcome = Current.Unit

  let re_valid_name = Str.regexp "^[A-Za-z][-0-9A-Za-z_]*$"

  let validate_name name =
    if not (Str.string_match re_valid_name name 0) then
      Fmt.failwith "Invalid unikernel name %S" name

  let kill name =
    let cmd = [ "albatross-client-local"; "destroy"; name ] in
    ("", Array.of_list cmd)

  let redeploy ~location ~args name =
    let cmd =
      [
        "albatross-client-local";
        "create";
        name;
        "--net=service:br1";
        location;
        "--mem=256";
        "--arg=" ^ String.concat " " args;
      ]
    in
    ("", Array.of_list cmd)

  let run image =
    Raw.Cmd.docker [ "container"; "run"; "-d"; Raw.Image.hash image ]

  let docker_cp src dst = Raw.Cmd.docker [ "cp"; src; dst ]

  let publish No_context job { Key.name } { Value.image; args } =
    Current.Job.log job "Deploy %a -> %s" Raw.Image.pp image name;
    validate_name name;
    Current.Job.start job ~level:Current.Level.Dangerous >>= fun () ->
    (* Extract unikernel image from Docker image: *)
    with_tmp ~prefix:"ocurrent-deployer-" ~suffix:".hvt" @@ fun tmp_path ->
    Raw.Cmd.with_container ~docker_context:None ~job ~kill_on_cancel:true
      (run image ~docker_context:None) (fun id ->
        let src = Printf.sprintf "%s:/unikernel.hvt" id in
        Current.Process.exec ~cancellable:true ~job
          (docker_cp ~docker_context:None src tmp_path))
    >>!= fun () ->
    (* Kill remote service (it's okay if it fails because the service
       might not exist.) *)
    Current.Process.exec ~cancellable:true ~job (kill name) >>= fun _ ->
    (* Restart remote service: *)
    Current.Process.exec ~cancellable:true ~job
      (redeploy ~location:tmp_path ~args name)

  let pp f (key, _v) = Fmt.pf f "@[<v2>deploy %s@]" key.Key.name
  let auto_cancel = true
end

module Deploy = Current_cache.Output (Op)
module Docker = Current_docker.Default

let[@warning "-32"] deploy ~name ~args image =
  Current.component "deploy %s" name
  |> let> image = image in
     Deploy.set Op.No_context { Op.Key.name }
       { Op.Value.image = Docker.Image.hash image |> Raw.Image.of_hash; args }
