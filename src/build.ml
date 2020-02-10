module Git = Current_git
module Github = Current_github

let daily = Current_cache.Schedule.v ~valid_for:(Duration.of_day 1) ()

module Make (T : S.T) = struct
  let repo ~git ~name build_specs =
    let root = Current.return ~label:("deploy-" ^ name) () in
    Current.with_context root @@ fun () ->
    let deployments =
      Current.all
        (build_specs
        |> List.map (fun (build_info, deploys) ->
               Current.all
                 (deploys
                 |> List.map (fun (branch, deploy_info) ->
                        let src =
                          match git with
                          | `Local git ->
                              Git.Local.commit_of_ref git
                                ("refs/heads/" ^ branch)
                          | `Github { Github.Repo_id.owner; name } ->
                              Git.clone ~schedule:daily ~gref:branch
                                (Fmt.str "https://github.com/%s/%s.git" owner
                                   name)
                        in
                        T.deploy build_info deploy_info src))))
      |> Current.collapse ~key:"repo" ~value:name ~input:root
    in
    deployments
end
