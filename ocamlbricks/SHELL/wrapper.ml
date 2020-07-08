(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2007  Jean-Vincent Loddo

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

(** Handling shell scripts in {e OCaml}. A general technique for wrapping
    shell commands or scripts is proposed in this module.
    The technique is applied in the module {!Shell} for building a significative set
    of ready-to-use wrappers corresponding to the most famous {e Unix} tools
    ({b grep}, {b dd}, {b tar},..).
*)

open Sugar;;

(** A {e command} is a string. *)
type command = string;;

(** A {e content} is a string. *)
type content = string;;

(** An {e argument} is a string. *)
type arg  = string ;;

(** A {e call} is a directly executable command, as for instance, ["ls"] or ["wc -l"] or ["cat | grep -v"]. *)
type call = string;;

(** A {e script} is a command containing some positional parameters [$1], [$2],...
    as for instance ["test -d $1 && echo true"].
    A script is not directly executable but can be easily {e enveloped} in a shell function
    in order to become executable by the shell interpreter. *)
type script = string;;

(** {2 Envelop} *)

(** Envelop a script into a function followed by a call of this function.

{b Example}:
{[# print_endline (envelop "test -d $1");;
function auxfun418234 () {
test -d $1
}
auxfun418234
  : unit = ()
]}*)
let envelop ?(name:string=("auxfun"^(string_of_int (Random.int 819200)))) (script:script) : call =
 ("function "^name^" () {\n"^script^"\n}\n"^name)
;;

(** {2 Wrapper} *)

(**
{[

                                           ?args:'a
                                              |
                                        +-----+-----+
                                        |    ?at    | argument(s)
                                   ?opt +-----+-----+ treatment
                                     |        |
                                   +----------+--+
             +-----------+         | Unix.shell  |         +-----------+
?input:'b -->+    ?it    +-------->+             +-------->+    ~ot    +-->'c
             +-----------+         |   command   |         +-----------+
            input treatment        +-------------+        output treatment

]}
*)

(** General constructor for shell encapsulation:

    - the function [~it] (the {e input treatment}, by default [None]) represent the action
     to execute before the [command], in order to transform a value of a
     type ['b] into a [string]; the result
     will be used as {b standard input} for the [command];

    - the function [~ot] (the {e output treatment}) represent the action
      to execute after the [command]
      in order to transform its {b standard output} (a [string])
      in a value of an arbitrary type ['c];

    - the function [~at] (the {e argument treatment}, by default [None]) permits a similar
      re-arrangement of the signature,
      but for the argument(s) of the command, which could be of any type ['a] (then
      also a tuple). This function converts the argument(s) in a string,
      which is the suitable type for the [command];

    - options (by default [~opt=""]) are appended as-is at right side of the
      command and before the string representation of arguments.

    If the flag [~script] is set the [command] is enveloped in order to allow the
    use of positionnal parameters [$1], [$2],... By default [~script=false].

    The function raises a failure if an argument or an input is provided
    (in the form [Some v])
    while the corresponding treatment is undefined (equals to [None]).
*)
let make

    ?(at:(('c->string) option)=None)
    ?(it:(('a->string) option)=None)
    ~(ot:(string->'b))
    ?(script=false)
     (cmd:command)
    ?(opt="")
    ?(args:('c option)=None) ?(input:('a option)=None) () =

    let cmd = if script then envelop cmd else cmd in

    let perform_treat t x = match (t,x) with
      | ((Some f), (Some x)) -> (f x)
      | (    _   ,  None)    -> ""
      | ( None   , (Some x)) -> failwith "Wrapper.make: argument provided without a treatment" in

    let args  = perform_treat at args  in
    let input = perform_treat it input in

    (cmd^" "^opt^" "^args^"\n") |> ((UnixExtra.shell ~trace:false ~input) ||> ot )
;;

(** {3 Text filters} *)

(** This constructor represent a specialization of the function {!make}
    for building wrappers dealing with texts (string lists):
- the input treatment  [~it] is set to [Some String.Text.to_string]
- the output treatment [~ot] is set to [String.Text.of_string]
 *)
let textfilter
    ?(at:(('c->string) option)=None)
    ?(script=false)
     (cmd:command)
    ?(opt="")
    ?(args:('c option)=None) (x:string list)

    = make
       ~at ~script
       ~it:(Some StringExtra.Text.to_string)
       ~ot:StringExtra.Text.of_string cmd
       ~opt ~args ~input:(Some x) ();;


(** {2 Treatments} *)

(** Common treatments for parameters, inputs and outputs. All treatments are value
    of the type [('a -> 'b) option]. *)
module Treat = struct

 (* {b Input/Argument treatments} *)

 (** Nothing to do (identity function). *)
 let identity = Some (fun x->x) ;;

 (** Simple quote the argument. Sometimes, the argument of the filter must be envelopd
    into simple quotes, as for [awk] and [sed], in order to prevent problems with special chars. *)
 let quote = Some (fun x -> "'"^x^"'");;

 (* {b Output treatments} *)

 (** Make your boolean scripts with this output treatment *)
 let is_true =
   (StringExtra.chop ||> ((=) "true")) ;;

end;; (* module Treat *)

(** {2 Examples}

Basically, the wrapper constructor may be used in a "quick and easy" way using strings
as parameters of the resulting wrapper. Instead, the more sofisticated way constists
in defining a real abstract syntax for parameters and/or inputs, in order to avoid
bad calls of the wrapper at compile-time.
*)

(** {3 Quick and easy wrapper} *)


(**{[
(* A wrapper for the command date *)
let date ?(opt="") ?(arg="") () =
 make ~at:Treat.identity ~ot:String.chop "date" ~args:(Some arg) ~opt () ;;

(* Examples of usage: *)

# date () ;;
  : string = "lun avr 16 14:28:57 CEST 2007"

# date ~opt:"-r" ~arg:"shell.ml" () ;;
  : string = "sam avr 14 16:58:22 CEST 2007"

# date ~arg:"-r shell.ml" () ;;
  : string = "sam avr 14 16:58:22 CEST 2007"

]}
*)

(** {3 A more sofisticated wrapper} *)

(**{[
(* A wrapper for the command date with an abstract syntax for parameters. *)
module Date = struct

 (* (1) Define your abstract syntax (for parameters and/or input and/or output).
        In this case for parameters: *)
 type options  = Option_f of string | Option_r of string | Option_R ;;
 type synopsis = options list ;;

 (* (2) Define your conversion(s) *)
 let string_of_options = function
  | Option_f x -> "-f "^x
  | Option_r x -> "-r "^x
  | Option_R   -> "-R "
 ;;

 let string_of_synopsis = String.merge_map string_of_options;;

 (* (3) Apply the wrapper constructor *)
 let date (args:synopsis) =
  make ~at:(Some string_of_synopsis) ~ot:String.chop "date" ~args:(Some args) ()
 ;;
end;;

(* Example of usage *)
# date [Option_r "shell.ml"];;
  : string = "sam avr 14 16:58:22 CEST 2007"
]}*)





