module type T = sig
  type build_info
  type deploy_info

  val deploy :
    build_info ->
    deploy_info ->
    Current_git.Commit.t Current.t ->
    unit Current.t
end
