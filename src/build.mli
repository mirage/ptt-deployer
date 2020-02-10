module Make (T : S.T) : sig
  val repo :
    git:[ `Local of Current_git.Local.t | `Github of Current_github.Repo_id.t ] ->
    name:string ->
    (T.build_info * (string * T.deploy_info) list) list ->
    unit Current.t
  (** [repo ~src builds] is an OCurrent pipeline to
        handle all builds and deployments of a given git repository. 
        Each build is a [(build_info, [branch, deploy_info])] pair.
        It builds every branch using [T.build], and deploys the
        given branches using [T.deploy]. *)
end
