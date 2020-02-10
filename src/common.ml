module E = Current_albatross_deployer

let get_ip =
  E.get_ip
    ~blacklist:[ Ipaddr.V4.of_string_exn "10.0.0.1" ]
    ~prefix:(Ipaddr.V4.Prefix.of_string_exn "10.0.0.1/24")

let collapse ~key ~value ~label v =
  let input = Current.return ~label () in
  Current.with_context input (fun () -> v)
  |> Current.collapse ~key ~value ~input
