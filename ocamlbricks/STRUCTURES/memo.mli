(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2011-2019 Jean-Vincent Loddo

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

(** Simple function memoization.*)

val default_size : int

(** Transform a function into its memoized version. *)
val memoize :
  ?trace_faults:unit -> ?trace_success:unit -> ?size:int ->
  ?sharing:('b Extreme_sharing.identity option) ->
  ?skip:('a -> bool) -> (* skip both memoization and codomain-values sharing *)
  ?ht:('a,'b) Hashtbl.t ->
  ('a -> 'b) -> 'a -> 'b

(** In order to manually manage the memory allocation it may be useful to get also the hash table: *)
val memoize_and_get_table :
  ?trace_faults:unit -> ?trace_success:unit -> ?size:int ->
  ?sharing:('b Extreme_sharing.identity option) ->
  ?skip:('a -> bool) ->
  ('a -> 'b) -> ('a -> 'b) * ('a,'b) Hashtbl.t

(** Memoize a recursive scheme: *)
val memoize_scheme :
  ?trace_faults:unit -> ?trace_success:unit -> ?size:int ->
  ?sharing:('b Extreme_sharing.identity option) ->
  ?skip:('a -> bool) ->
  ?ht:('a,'b) Hashtbl.t ->
  (('a -> 'b) -> ('a -> 'b)) -> 'a -> 'b

val memoize_scheme_and_get_table :
  ?trace_faults:unit -> ?trace_success:unit -> ?size:int ->
  ?sharing:('b Extreme_sharing.identity option) ->
  ?skip:('a -> bool) ->
  (('a -> 'b) -> ('a -> 'b)) -> ('a -> 'b) * ('a,'b) Hashtbl.t

(** Memoize a binary simmetric operator (f x y = f y x): *)
val memoize_binary_simmetric :
  ?trace_faults:unit -> ?trace_success:unit -> ?size:int ->
  ?sharing:('b Extreme_sharing.identity option) ->
  ?skip:('a -> 'a -> bool) -> (* skip both memoization and codomain-values sharing *)
  ?ht:(('a * 'a),'b) Hashtbl.t ->
  ('a -> 'a -> 'b) -> ('a -> 'a -> 'b)


(* Examples:

# let fact self x = if x=0 then 1 else x * (self (x-1)) ;;
val fact : (int -> int) -> int -> int

# let fact' = Memo.memoize_scheme ~trace_faults:() ~trace_success:() ~skip:(fun x -> x>9) fact ;;
val fact' : int -> int

# fact' 5 ;;
[19740.0]: Memo.memoize: cache fault for hash key 378313623 (cumulated faults 100.0%).
[19740.0]: Memo.memoize: cache fault for hash key 127382775 (cumulated faults 100.0%).
[19740.0]: Memo.memoize: cache fault for hash key 152507349 (cumulated faults 100.0%).
[19740.0]: Memo.memoize: cache fault for hash key 648017920 (cumulated faults 100.0%).
[19740.0]: Memo.memoize: cache fault for hash key 883721435 (cumulated faults 100.0%).
[19740.0]: Memo.memoize: cache fault for hash key 129913994 (cumulated faults 100.0%).
- : int = 120

# fact' 5 ;;
[19740.0]: Memo.memoize: success for hash key 378313623 (cumulated success 14.3%).
- : int = 120

# fact' 6 ;;
[19740.0]: Memo.memoize: cache fault for hash key 899338544 (cumulated faults 87.5%).
[19740.0]: Memo.memoize: success for hash key 378313623 (cumulated success 22.2%).
- : int = 720

# fact' 9 ;;
[19740.0]: Memo.memoize: cache fault for hash key 531229256 (cumulated faults 80.0%).
[19740.0]: Memo.memoize: cache fault for hash key 894170852 (cumulated faults 81.8%).
[19740.0]: Memo.memoize: cache fault for hash key 631987845 (cumulated faults 83.3%).
[19740.0]: Memo.memoize: success for hash key 899338544 (cumulated success 23.1%).
- : int = 362880

# fact' 9 ;;
[19740.0]: Memo.memoize: success for hash key 531229256 (cumulated success 28.6%).
- : int = 362880

# fact' 10 ;;
[19740.0]: Memo.memoize: success for hash key 531229256 (cumulated success 33.3%).
- : int = 3628800

# fact' 11 ;;
[19740.0]: Memo.memoize: success for hash key 531229256 (cumulated success 37.5%).
- : int = 39916800

# fact' 12 ;;
[19740.0]: Memo.memoize: success for hash key 531229256 (cumulated success 41.2%).
- : int = 479001600

*)
