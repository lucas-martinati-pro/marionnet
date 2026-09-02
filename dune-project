(lang dune 3.7)

;; This file is part of Marionnet, a virtual network laboratory
;; Copyright (C) 2023  Jean-Vincent Loddo
;; Copyright (C) 2023  Université Sorbonne Paris Nord (USPN)
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 2 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(name "marionnet")

(using dune_site 0.1)

(generate_opam_files true)

(source
  (uri "git+https://git.launchpad.net/marionnet"))

(version "1.0.x")  ;; the publication series; the patch level is derived (see META)

(authors
  "Jean-Vincent Loddo"
  "Luca Saiu")

(maintainers
  "Jean-Vincent Loddo")

(license "GPL-2.0-or-later")

(documentation https://www.marionnet.org)

(package
  (name "marionnet")
  (synopsis "A virtual network laboratory")
  (description "A virtual network laboratory for learning TCP/IP networks")
  (depends ocaml dune dune-site)
  ;; i18n: the gettext `.mo' catalogues are installed into this site (section
  ;; `share' -> <prefix>/share/marionnet/locale/<lang>/LC_MESSAGES/marionnet.mo)
  ;; and located at run-time via the generated Marionnet_sites.Sites.locale
  ;; (relocatable), see i18n/dune and bin/gettext.ml.
  (sites (share locale))
  (tags
    ("Internet" "TCP/IP" "network" "laboratory"
     "Ipv4" "Ipv6" "TCP" "UDP" "SCTP" "ICMP" "ARP" "Ethernet"))
  )

