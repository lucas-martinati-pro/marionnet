(* GPL-2.0-or-later. Real threads exercise reservations and ownership. *)
let require condition message = if not condition then failwith message
let ticket = function Some ticket -> ticket | None -> failwith "Reservation refused"
let () =
  let guard = Task_guard.create () in
  let first = ticket (Task_guard.reserve guard ~key:"project" ~label:"Saving") in
  require (Task_guard.reserve guard ~key:"project" ~label:"Opening" = None)
    "A queued task must block duplicates before its worker starts";
  require (not (Task_guard.owned guard "project")) "A reservation has no owner yet";
  let worker = Thread.create (fun () ->
    Task_guard.enter guard first;
    require (Task_guard.owned guard "project") "Nested calls must recognize their worker";
    require (List.mem_assoc "project" (Task_guard.active guard)) "Active work must be observable") () in
  Thread.join worker;
  require (not (Task_guard.owned guard "project")) "Another thread cannot inherit ownership";
  Task_guard.release guard first;
  let second = ticket (Task_guard.reserve guard ~key:"project" ~label:"Opening") in
  Task_guard.release guard first;
  require (List.mem_assoc "project" (Task_guard.active guard)) "Old cleanup cannot release newer work";
  let other = ticket (Task_guard.reserve guard ~key:"component:1" ~label:"Starting") in
  Task_guard.release guard other;
  Task_guard.release guard second;
  let winners = Array.make 24 None in
  let workers = Array.init 24 (fun index -> Thread.create (fun () ->
    winners.(index) <- Task_guard.reserve guard ~key:"same-component" ~label:"Start") ()) in
  Array.iter Thread.join workers;
  let won = Array.to_list winners |> List.filter_map (fun x -> x) in
  require (List.length won = 1) "Concurrent submissions must yield exactly one reservation";
  List.iter (Task_guard.release guard) won;
  let failing = ticket (Task_guard.reserve guard ~key:"project" ~label:"Saving") in
  (try Fun.protect ~finally:(fun () -> Task_guard.release guard failing)
    (fun () -> raise Exit) with Exit -> ());
  require (Task_guard.active guard = []) "Failures must leave no busy resource";
  print_endline "PASS: task reservations, synchronous nesting, concurrent duplicates and cleanup"
