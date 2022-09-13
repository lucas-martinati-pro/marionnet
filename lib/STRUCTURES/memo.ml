(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007-2019 Jean-Vincent Loddo

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. *)

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

module Log = Ocamlbricks_log

(** The default size of hash tables. *)
let default_size = 251;;

(** Make the function transformer and return its associated hash table. *)
let make ?trace_faults ?trace_success ?(size=default_size) ?skip ?(ht=Hashtbl.create size) () =
  let find = Hashtbl.find ht in
  let replace = Hashtbl.replace ht in
  let mill =
    match trace_faults, trace_success, skip with
    (* --- *)
    | None, None, None ->
       (fun f0 f1 x ->
          try
            find x
          with Not_found ->
            begin
              let y = f1 x in
              let () = replace x y in
              y
            end)
    (* --- *)
    | (Some ()), None, None ->
        let calls, success = (ref 0), (ref 0) in
        (fun f0 f1 x ->
           let () = incr calls in
           try
             let result = find x in
             let () = incr success in
             result
           with Not_found ->
             begin
               Log.printf2
                 "Memo.memoize: cache fault for hash key %d (cumulated faults %4.1f%%).\n"
                 (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 (!calls - !success) !calls);
               let y = f1 x in
               let () = replace x y in
               y
             end)
    (* --- *)
    | None, (Some ()), None ->
        let calls, success = (ref 0), (ref 0) in
        (fun f0 f1 x ->
           let () = incr calls in
           try
             let result = find x in
             let () = incr success in
             let () = Log.printf2 "Memo.memoize: success for hash key %d (cumulated success %4.1f%%).\n"
               (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 !success !calls)
             in
             result
           with Not_found ->
             begin
               let y = f1 x in
               let () = replace x y in
               y
             end)
    (* --- *)
    | (Some ()), (Some ()), None ->
         let calls, success = (ref 0), (ref 0) in
         (fun f0 f1 x ->
            let () = incr calls in
            try
              let result = find x in
              let () = incr success in
              let () = Log.printf2 "Memo.memoize: success for hash key %d (cumulated success %4.1f%%).\n"
                (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 !success !calls)
              in
              result
            with Not_found ->
              begin
                Log.printf2
                  "Memo.memoize: cache fault for hash key %d (cumulated faults %4.1f%%).\n"
                  (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 (!calls - !success) !calls);
                let y = f1 x in
                let () = replace x y in
                y
              end)
    (* --- *)
    (* --- skip parts start here (f0 may be used) --- *)
    (* --- *)
    | None, None, (Some skip) ->
        (fun f0 f1 x ->
           if skip x then f0 x else (* as usual *)
           try
             find x
           with Not_found ->
             begin
               let y = f1 x in
               let () = replace x y in
               y
             end)
    (* --- *)
    | (Some ()), None, (Some skip) ->
         let calls, success = (ref 0), (ref 0) in
         (fun f0 f1 x ->
            if skip x then f0 x else (* as usual *)
            let () = incr calls in
            try
              let result = find x in
              let () = incr success in
              result
            with Not_found ->
              begin
                Log.printf2
                  "Memo.memoize: cache fault for hash key %d (cumulated faults %4.1f%%).\n"
                  (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 (!calls - !success) !calls);
                let y = f1 x in
                let () = replace x y in
                y
              end)
    (* --- *)
    | None, (Some ()), (Some skip) ->
        let calls, success = (ref 0), (ref 0) in
        (fun f0 f1 x ->
           if skip x then f0 x else (* as usual *)
           let () = incr calls in
           try
             let result = find x in
             let () = incr success in
             let () = Log.printf2 "Memo.memoize: success for hash key %d (cumulated success %4.1f%%).\n"
               (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 !success !calls)
             in
             result
           with Not_found ->
             begin
               let y = f1 x in
               let () = replace x y in
               y
             end)
    (* --- *)
    | (Some ()), (Some ()), (Some skip) ->
         let calls, success = (ref 0), (ref 0) in
         (fun f0 f1 x ->
            if skip x then f0 x else (* as usual *)
            let () = incr calls in
            try
              let result = find x in
              let () = incr success in
              let () = Log.printf2 "Memo.memoize: success for hash key %d (cumulated success %4.1f%%).\n"
                (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 !success !calls)
              in
              result
            with Not_found ->
              begin
                Log.printf2
                  "Memo.memoize: cache fault for hash key %d (cumulated faults %4.1f%%).\n"
                  (Hashtbl.hash x) (PervasivesExtra.percentage_fraction ~decimals:1 (!calls - !success) !calls);
                let y = f1 x in
                let () = replace x y in
                y
              end)
  (* --- *)
  in (* mill *)
  (mill, ht)

(* --- *)

(* f0 will be used when memoization will be skipped, f1 to produce an output that will be stored in the hash table: *)
let duo_f0_f1 ?sharing () =
  match sharing with
  | None    -> fun f -> (f, f)
  | Some opt_id ->
      let co_attach = Extreme_sharing.co_attach ?id:(opt_id) in
      fun f -> (f, co_attach f)

let memoize ?trace_faults ?trace_success ?size ?sharing ?skip ?ht =
  let (mill, _ht) = make ?trace_faults ?trace_success ?size ?skip ?ht () in
  let duo_f0_f1 = duo_f0_f1 ?sharing () in
  fun f -> let (f0, f1) = duo_f0_f1 f in mill f0 f1

(* --- *)

let memoize_and_get_table ?trace_faults ?trace_success ?size ?sharing ?skip =
  let (mill, ht) = make ?trace_faults ?trace_success ?size ?skip ?ht:None () in
  let duo_f0_f1 = duo_f0_f1 ?sharing () in
  fun f -> let (f0, f1) = duo_f0_f1 f in (mill f0 f1, ht)

(* --- *)

let memoize_scheme ?trace_faults ?trace_success ?(size=default_size) ?sharing ?skip ?(ht=Hashtbl.create size) =
  let (mill, _) = make ?trace_faults ?trace_success ~size ?skip ~ht () in
  let duo_f0_f1 = duo_f0_f1 ?sharing () in
  fun scheme ->
    let rec f x = scheme (mill f f) x in
    let (f0, f1) = duo_f0_f1 f in
    mill f0 f1

(*(* ALTERNATIVE *)
let memoize_scheme_ALT ?trace_faults ?trace_success ?(size=default_size) ?sharing ?skip ?(ht=Hashtbl.create size) =
  let (mill, _) = make ?trace_faults ?trace_success ~size ?skip ~ht () in
  let duo_f0_f1 = duo_f0_f1 ?sharing () in
  fun scheme ->
    let scheme' f =
      let (f0, f1) = duo_f0_f1 f in
      scheme (mill f0 f1)
    in
    let rec f x = scheme' f x in
    mill f f*)

(* --- *)

let memoize_scheme_and_get_table ?trace_faults ?trace_success ?(size=default_size) ?sharing ?skip =
  let ht = Hashtbl.create size in
  let (mill, _)  = make ?trace_faults ?trace_success ~size ?skip ~ht () in
  let duo_f0_f1 = duo_f0_f1 ?sharing () in
  fun scheme ->
    let rec f x = scheme (mill f f) x in
    let (f0, f1) = duo_f0_f1 f in
    (mill f0 f1, ht)


(*(* ALTERNATIVE *)
let memoize_scheme_and_get_table_ALT ?trace_faults ?trace_success ?(size=default_size) ?sharing ?skip =
  let ht = Hashtbl.create size in
  let (mill, _)  = make ?trace_faults ?trace_success ~size ?skip ~ht () in
  let duo_f0_f1 = duo_f0_f1 ?sharing () in
  fun scheme ->
    let scheme' f =
      let (f0, f1) = duo_f0_f1 (f) in
      scheme (mill f0 f1)
    in
    let rec f x = scheme' f x in
    (mill f f, ht)*)

(* Memoize a binary simmetric operator (f x y = f y x): *)
let memoize_binary_simmetric ?trace_faults ?trace_success ?size ?sharing ?skip ?ht f =
  let f', ht =
    match ht with
    | None ->  memoize_and_get_table ?trace_faults ?trace_success ?size ?sharing (fun (x1,x2) -> f x1 x2)
    | Some ht -> (memoize ?trace_faults ?trace_success ?size ?sharing ~ht (fun (x1,x2) -> f x1 x2), ht)
  in
  fun x1 x2 ->
    let (x1, x2) =
      try
        if (x1 < x2) then (x1, x2) else (x2, x1)
      with
        Invalid_argument _ (* "equal: functional value" *) ->
          (if Hashtbl.mem ht (x1,x2) then (x1,x2) else (x2,x1))
    in
    f' (x1,x2)

