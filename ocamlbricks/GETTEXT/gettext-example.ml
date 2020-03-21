(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2009, 2010  Luca Saiu

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


(* This is just a trivial example showing how to use our gettext wrapper: *)

(* This uses the translations of GNU Hello, (http://www.gnu.org/software/hello)
   which are assumed to be found in /usr/share/locale. Of course you can change
   this: *)
module Gettext =
  Gettext_builder.Make(struct
     let text_domain = "hello";;
     let directory = "/usr/share/locale";;
    end);;

(* We want to just use s_ and f_: *)
open Gettext;;

(* The strings below are really used in GNU Hello. Of course you can't replace
   them with other messages, unless you also have translations: *)
Printf.printf "%s" (s_ "hello, world\n");;
Printf.printf (f_ "hello, world\n");;
Printf.printf (f_ "Try `%s --help' for more information.\n") "foo";;
Printf.printf (f_ "Report bugs to <%s>.\n") "foo@foo.foo";;
