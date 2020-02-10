module Docker = Current_docker.Default

let timeout = Duration.of_min 50 (* Max build time *)

type build_info = { dockerfile : string; args : string list }
type deploy_info = { service : string }

let build_image { dockerfile; args } src =
  let args = args in
  let build_args =
    List.map (fun x -> [ "--build-arg"; x ]) args |> List.concat
  in
  let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
  Docker.build (`Git src) ~build_args ~dockerfile ~label:"docker-build"
    ~pull:true ~timeout

let deploy build_info { service } src =
  let image = build_image build_info src in
  Docker.service ~name:service ~image ()
