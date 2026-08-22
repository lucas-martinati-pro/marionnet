(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2026  Jean-Vincent Loddo

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

(* --- *)
module FilenameExtra = Ocamlbricks.FilenameExtra
(* --- *)

(** Am I an installed binary, or a binary of this repository's build tree?
    The single place where the whole application answers that question. *)

(** Where the data of THIS repository are, when the binary runs from the build tree,
    laid out as an installation prefix: <root>/_build/install/default/share/marionnet/.
    In that case dune-site knows nothing (the %%DUNE_PLACEHOLDER%% of i18n/Locations.ml is
    rewritten by `dune install' only), but `dune build' produces that directory anyway,
    where `gui/', `images/' and `locale/' are links towards the built copies of this
    repository. Recognizing the shape <root>/_build/default/bin/<exe> is deliberate and
    narrow: an installed binary never matches it, and this is the only place in the code
    which knows about `_build'.
    ---
    Note that the answer is NOT a substitute for the installation prefix as a whole: the
    directory returned here has an EMPTY `filesystems/' and NO `kernels/' at all (measured
    2026-08-22). Only the data versioned in this repository may be taken from it. *)
let share_directory () =
  let exe = FilenameExtra.to_absolute (Sys.executable_name) in
  let bin_dir     = Filename.dirname exe in
  let default_dir = Filename.dirname bin_dir in
  let build_dir   = Filename.dirname default_dir in
  if (Filename.basename bin_dir) = "bin"
  && (Filename.basename default_dir) = "default"
  && (Filename.basename build_dir) = "_build"
  then
    Some (FilenameExtra.concat_list [build_dir; "install"; "default"; "share"; Meta.name])
  else
    None
;;
