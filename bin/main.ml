let () = print_endline "Hello, World!";;
module Obr = Ocamlbricks;;
let () = Printf.printf "RESULT IS %d\n" (Obr.StringExtra.count "abbcccdddaaaaaaaaa" 'c') ;;
let () = print_endline (Obr.UnixExtra.cat "/etc/fstab") ;;

