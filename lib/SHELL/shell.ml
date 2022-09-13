(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo
   Updated in 2008 by Jean-Vincent Loddo and Luca Saiu

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

(** A collection of simple wrappers for the most famous
    {e Unix} tools ({b grep}, {b dd}, {b tar},..). *)

open Sugar;;
module Treat = Wrapper.Treat

(** A {e filename} is a string. *)
type filename = string;;

(** A {e filexpr} is a string (with meta-characters, for instance ["/etc/*tab"]). *)
type filexpr = string;;

(** A {e foldername} is a string. *)
type foldername = string;;

type line = string
type text = line list

(** {2 Text filters} *)

(** Wrapper for the {b awk} unix filter. The first argument is the awk program,
    the second one is the input text (string list).
{b Example}:
{[# awk "{print $1}" ["Hello World";"Bye Bye"];;
  : string list = ["Hello"; "Bye"]
]}*)
let awk ?(opt="") prog text = Wrapper.textfilter ~at:Treat.quote "awk" ~opt ~args:(Some(prog)) text ;;


(** Wrapper for the {b cut} unix filter.
{b Example}:
{[#  cut "-d: -f2,3" ["AA:BB:CC:DD:EE:FF"];;
  : string list = ["BB:CC"]
]}*)
let cut args text = Wrapper.textfilter ~at:Treat.identity "cut" ~args:(Some(args)) text ;;


(** Wrapper for the {b head} unix filter. {b Examples}:
{[# head ["hello world"; "bye bye"];;
  : string list = ["hello world"; "bye bye"]

# head ~opt:"-1" ["hello world"; "bye bye"];;
  : string list = ["hello world"]]}*)
let head ?(opt="") text = Wrapper.textfilter "head" ~opt text ;;

(** Wrapper for the {b grep} unix filter. {b Examples}:
{[# grep "aa" ["aaa";"bbb";"caa";"ddd"];;
  : string list = ["aaa"; "caa"]

# grep ~opt:"-v" "aa" ["aaa";"bbb";"caa";"ddd"];;
  : string list = ["bbb"; "ddd"]
]}*)
let grep ?(opt="") regexp text = Wrapper.textfilter ~at:Treat.quote "grep" ~opt ~args:(Some(regexp)) text ;;

(** Wrapper for the {b nl} unix filter. {b Examples}:
{[# nl ["first"; "second";"third"];;
  : string list = ["     1\tfirst"; "     2\tsecond"; "     3\tthird"]

# nl ~opt:"-w 1" ["first"; "second";"third"];;
  : string list = ["1\tfirst"; "2\tsecond"; "3\tthird"]
]}*)
let nl ?(opt="") text = Wrapper.textfilter "nl" ~opt text ;;


(** Wrapper for the {b sed} unix filter. By default [~opt="-e"]. {b Example}:
{[# sed "s/e/E/g" ["Hello World";"Bye Bye"];;
  : string list = ["HEllo World"; "ByE ByE"]
]}*)
let sed ?(opt="-e") prog text = Wrapper.textfilter ~at:Treat.quote "sed" ~opt ~args:(Some(prog)) text ;;

(** Wrapper for the {b sort} unix filter. {b Examples}:
{[# sort  ["Hello";"Salut"; "Ciao" ];;
  : string list = ["Ciao"; "Hello"; "Salut"]

# sort ~opt:"-r"  ["Hello";"Salut"; "Ciao" ];;
  : string list = ["Salut"; "Hello"; "Ciao"]
]}*)
let sort ?(opt="") text = Wrapper.textfilter "sort" ~opt text ;;


(** Wrapper for the {b tac} unix filter.  {b Example}:
{[# tac   ["Hello";"Salut"; "Ciao" ];;
  : string list = ["Ciao"; "Salut"; "Hello"]
]}*)
let tac ?(opt="") text = Wrapper.textfilter "tac" ~opt text ;;

(** Wrapper for the {b tail} unix filter. {b Examples}:
{[# tail   ["Hello";"Salut"; "Ciao" ];;
  : string list = ["Hello"; "Salut"; "Ciao"]

# tail ~opt:"-2"  ["Hello";"Salut"; "Ciao" ];;
  : string list = ["Salut"; "Ciao"]
]}*)
let tail ?(opt="") text = Wrapper.textfilter "tail" ~opt text ;;

(** Wrapper for the {b tee} unix filter.
    Filenames are quoted then merged with the blank separator.
{b Example}:
{[# tee ["foo.bar"] ["Salut"; "Hello"; "Ciao"];;
  : string list = ["Salut"; "Hello"; "Ciao"]

# Unix.cat "foo.bar";;
  : string = "Salut\nHello\nCiao\n"]
]}*)
let tee ?(opt="") (files:filename list) text =
  let args = List.map StringExtra.quote files in
  let args = String.concat " " args in
  Wrapper.textfilter ~at:Treat.identity "tee" ~opt ~args:(Some args) text ;;


(** Wrapper for the {b tr} unix filter. {b Example}:
{[# tr 'a' 'A' ["Salut"; "Hello"; "Ciao"];;
  : string list = ["SAlut"; "Hello"; "CiAo"]
]}*)
let tr ?(opt="") c1 c2 text =
 let s1 = StringExtra.quote (Char.escaped c1) in
 let s2 = StringExtra.quote (Char.escaped c2) in
 let args = String.concat " " [s1;s2] in
  Wrapper.textfilter ~at:Treat.identity "tr" ~opt ~args:(Some args) text ;;

(** Wrapper for the {b uniq} unix filter. {b Example}:
{[# uniq ["AA"; "BB"; "CC"; "CC"; "AA"];;
  : string list = ["AA"; "BB"; "CC"; "AA"]
]}*)
let uniq ?(opt="") text = Wrapper.textfilter "uniq" ~opt text ;;

(** {2 Text summary} *)

(** Wrapper for the {b wc -w} unix word counter. {b Example}:
{[# wc ["AA BB"; "CC"; "DD EE"];;
  : int = 5
]}*)
let wc text : int =
 Wrapper.make
   ~it:(Some StringExtra.Text.to_string)
   ~ot:(StringExtra.chop ||> int_of_string)
   "wc -w"
   ~input:(Some text) () ;;

(** Wrapper for the {b wc -c} unix char counter. In a {e strict} sense, the newline
    characters added to strings in order to trasform them in lines (if needed)
    are not counted. By default [strict=false].
{b Examples}:
{[# cc ["AA BB"; "CC"];;
  : int = 9

# cc ["AA BB\n"; "CC\n"];;
  : int = 9

# cc ~strict:true ["AA BB"; "CC"];;
  : int = 7
]}*)
let cc ?(strict=false) text : int =
 let it = Some(if strict then (String.concat "") else (StringExtra.Text.to_string)) in
 Wrapper.make
   ~it
   ~ot:(StringExtra.chop ||> int_of_string)
   "wc -c"
   ~input:(Some text) () ;;


(** {2 Filtering files} *)

(** Wrappers operating on filexpr and providing as result a text (string list). *)
module Files = struct

(** Expand a file expression (with meta-characters) into the list of existing files.
    The optional parameter [null] refers to the [nullglob] bash option. By default [null=false].

{[# Files.glob "/etc/*tab";;
  : string list = ["/etc/crontab"; "/etc/fstab"; "/etc/inittab"; "/etc/mtab"]
]}*)
let glob ?(null=false) (args:filexpr) =
  let shopt = ("shopt "^(if null then "-s" else "-u")^" nullglob\n") in
  let cmd = shopt^"for i in \"$@\"; do echo $i; done" in
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string cmd ~script:true ~args:(Some args) ();;

(** The following functions are wrappers of the homonymous unix command.
    The difference from the [Shell] versions is that they ignore their input
    and take a [filexpr] as unique argument. *)


(** Wrapper for the {b cat} unix filter. {b Examples}:
{[# wc (Files.cat "/etc/*tab");;
  : int = 1418

# wc (Files.cat ~opt:"-n" "/etc/*tab");;
  : int = 1691]}*)
 let cat ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "cat" ~opt ~args:(Some arg) ();;

 let cut  ?(opt="") (arg:filexpr) =
   Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "cut" ~opt ~args:(Some arg) ();;

 let head ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "head" ~opt ~args:(Some arg) ();;

 let file ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "file" ~opt ~args:(Some arg) ();;

 let nl ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "nl" ~opt ~args:(Some arg) ();;

 let sort ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "sort" ~opt ~args:(Some arg) ();;

 let tac  ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "tac" ~opt ~args:(Some arg) ();;

 let tail ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "tail" ~opt ~args:(Some arg) ();;

 let uniq ?(opt="") (arg:filexpr) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "uniq" ~opt ~args:(Some arg) ();;


end;;

(** {2 System info} *)

(** Wrapper for the {b date} unix command. {b Examples}:
{[# date ();;
  : string = "mar avr 17 21:06:30 CEST 2007"

#  date ~arg:"+%d-%m-%Y.%kh%M" ();;
  : string = "17-04-2007.21h06"
]}*)
let date ?(opt="") ?(arg="") () =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.chop "date" ~opt ~args:(Some arg) ();;


(** Wrapper for the {b id} unix command. {b Examples}:
{[# id ();;
  : string = "uid=3013(loddo) gid=1031(lcr) groupes=0(root),1031(lcr)"

# id ~opt:"-g" ();;
  : string = "1031"
]}*)
let id ?(opt="") ?(arg="") () =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.chop "id" ~opt ~args:(Some arg) ();;

(** Wrapper for the {b uname} unix command. {b Examples}:
{[# uname ();;
  : string = "Linux"

# uname ~opt:"-r" ();;
  : string = "2.6.16.27-0.6-smp"
]}*)
let uname ?(opt="") () = Wrapper.make ~ot:StringExtra.chop "uname" ~opt ();;

(** Wrapper for the {b whoami} unix command. {b Example}:
{[# whoami ();;
 : string = "loddo"
]}*)
let whoami () = Wrapper.make ~ot:StringExtra.chop "whoami" ();;


(** {2 Stuff} *)

(** {3 find} *)

(** Wrapper for find. {b Example}:
{[# find "/etc/*tab -name '*n*'";;
  : string list = ["/etc/crontab"; "/etc/inittab"]
]}*)
 let find (arg:string) =
  Wrapper.make ~at:Treat.identity ~ot:StringExtra.Text.of_string "find" ~args:(Some arg) ();;


(** {3 dd} *)


(** A quite sofisticated wrapper for dd. The input (first argument) and
    output (second argument) filenames are automatically quoted. {b Examples:}
{[# dd "/etc/fstab" "fstab.copy";;
2+1 records in
2+1 records out
1130 bytes (1,1 kB) copied, 0,00017 seconde, 6,6 MB/s
  : unit = ()

# dd ~ibs:(Some 256) ~obs:(Some 256) "/etc/fstab" "fstab.copy";;
4+1 records in
4+1 records out
1130 bytes (1,1 kB) copied, 0,000191 seconde, 5,9 MB/s
  : unit = ()
]}*)
let dd ?(ibs=None) ?(obs=None) ?(bs=None) ?(cbs=None) ?(skip=None) ?(seek=None) ?(count=None) ?(conv=None)
 (x:filename) (y:filename) =

 let iF   = " if="^(StringExtra.quote x) in
 let oF   = " of="^(StringExtra.quote y) in
 let ibs  = match ibs   with (Some n) -> " ibs="  ^ (string_of_int n) | _ -> "" in
 let obs  = match obs   with (Some n) -> " obs="  ^ (string_of_int n) | _ -> "" in
 let  bs  = match  bs   with (Some n) -> "  bs="  ^ (string_of_int n) | _ -> "" in
 let cbs  = match cbs   with (Some n) -> " cbs="  ^ (string_of_int n) | _ -> "" in
 let skip = match skip  with (Some n) -> " skip=" ^ (string_of_int n) | _ -> "" in
 let seek = match seek  with (Some n) -> " seek=" ^ (string_of_int n) | _ -> "" in
 let count= match count with (Some n) -> " count="^ (string_of_int n) | _ -> "" in
 let conv = match conv  with (Some n) -> " conv=" ^ (string_of_int n) | _ -> ""
 in
 let arg = (iF^oF^ibs^obs^bs^cbs^skip^seek^count^conv) in
 Wrapper.make ~at:Treat.identity ~ot:ignore "dd" ~args:(Some arg) ()
;;

(** {3 tar} *)

(** Wrapper for the command [tar -cz].
{b Example:}
{[# tgz_create "mysite.tgz" "/var/www/html /etc/httpd*";;
  : unit = ()
]}*)
let tgz_create ?(opt="") (fname:filename) (files:filexpr) =
  let at (t,e) = ((StringExtra.quote t)^" "^e) in
  Wrapper.make ~at:(Some at) ~ot:ignore ("tar "^opt^" -czf $@") ~script:true ~args:(Some (fname,files)) ()
;;


(** Wrapper for the command [tar -xz].
    The gzip compressed archive will be extracted in the specified folder.
{b Example:}
{[# tgz_extract "foo.tgz" "temp/";;
  : unit = ()
]}*)
let tgz_extract ?(opt="") (fname:filename) (rep:foldername) =
  let at (t,r) = ((StringExtra.quote t)^" "^(StringExtra.quote r)) in
  Wrapper.make ~at:(Some at) ~ot:ignore ("tar "^opt^" -C $2 -xzf $1") ~script:true ~args:(Some (fname,rep)) ()
;;


type pid = int

let get_children_by_the_external_command_ps ?(pid=Unix.getpid ()) () =
 let command = Printf.sprintf "ps --ppid %d -o pid --no-headers" pid in
 let result =
   List.map
     (fun x -> int_of_string (StringExtra.strip x))
     (StringExtra.Text.of_string (UnixExtra.shell (command)))
 in
 (* this filter may remove the `ps' process used before which is dead now: *)
 List.filter (UnixExtra.is_process_alive) result
;;

let get_children_by_ps = get_children_by_the_external_command_ps ;;

let rec get_descendants_by_ps ?(pid=Unix.getpid ()) () =
 let children = get_children_by_ps ~pid () in
 List.concat (List.map (fun pid -> pid::(get_descendants_by_ps ~pid ())) children)
;;

let kill_children_by_ps ?(pid=Unix.getpid ()) () =
 let get_children () = get_children_by_ps ~pid () in
 (* --- Step 1: send SIGTERM (15) to children: *)
 let children = get_children () in
 if children = [] then () (* return *) else (* continue *)
 let () = List.iter (fun pid -> try Unix.kill pid 15 with _ -> ()) (List.rev children) in
 (* --- Step 2: send SIGINT (2) to remaining children: *)
 let children = get_children () in
 if children = [] then () (* return *) else (* continue *)
 let () = List.iter (fun pid -> try Unix.kill pid 2 with _ -> ()) (List.rev children) in
 (* --- Step 3: send SIGKILL (9) to remaining children: *)
 let children = get_children () in
 if children = [] then () (* return *) else (* continue *)
 let () = List.iter (fun pid -> try Unix.kill pid 9 with _ -> ()) (List.rev children) in
 ()
;;

let rec kill_descendants_by_ps ?(pid=Unix.getpid ()) () =
 (* --- Step 1: recursively kill children's descendance: *)
 let children = get_children_by_ps ~pid () in
 if children = [] then () (* return *) else (* continue *)
 let () = List.iter (fun pid -> kill_descendants_by_ps ~pid ()) (List.rev children) in
 (* --- Step 2: kill now the children: *)
 kill_children_by_ps ~pid ()
;;

(** Escape blanks, parenthesis, '&', '*' and '?'.
{b Example:}
{[# escaped_filename "foo (v0.1)" ;;
  : string = "foo\\ \\(v0.1\\)"
]}*)
let escaped_filename : string -> string =
  StrExtra.Global.substitute (Str.regexp "[ )(&*?]") (Printf.sprintf "\\%s")
;;

