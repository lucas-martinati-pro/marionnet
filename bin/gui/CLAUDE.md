# bin/gui/ — complétion GTK

Patron : `gui_glade3.xml` (source de vérité de l'interface, éditer avec `make edit-gui`) →
`bin/gui.ml` (accès typés aux widgets) → les modules d'ici **finissent** l'interface par code.
La plupart sont des foncteurs `Make (State : sig val st : State.globalState end)` appliqués
dans `bin/marionnet.ml` — c'est l'injection de l'état global dans la GUI.

**Piège majeur** : `bin/gui.ml` a été généré par lablgladecc **puis modifié à la main**.
Aucune procédure de régénération n'est établie → ne JAMAIS relancer lablgladecc sur
`gui_glade3.xml` pour remplacer `gui.ml` ; éditer `gui.ml` à la main en cohérence avec le xml.

Discipline threads : GTK depuis le seul thread principal ; depuis un autre thread, passer par
`bin/gMain_actor.ml`. Workaround lablgtk connu : `~label:""` obligatoire dans
`GMenu.image_menu_item` (cf. gui_toolbar_COMPONENTS_layouts).

Rôles des fichiers : voir `CLAUDE-file-overview.md`.
Chantier GUI : charger le skill `marionnet-gui`.
