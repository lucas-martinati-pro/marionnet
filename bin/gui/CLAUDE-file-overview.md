# bin/gui/ — index des rôles (une ligne par fichier)

> Généré depuis l'audit du 2026-07-06 (`docs/audit-marionnet-20260706.md`). `?` = incertain.

- `gui_bricks.ml/.mli` — boîte à outils des dialogues : `form` (tables étiquetées + tooltips), spin/combo/entrées IP, questions oui/annuler, wrappers réactifs (Cortex). Socle de tous les dialogues composants.
- `gui_window_MARIONNET.ml` — complétion de la fenêtre principale (labels, sensibilité, sous-foncteurs, expose `Motherboard`).
- `gui_menubar_MARIONNET.ml` — menus Projet/Options/… : callbacks projet (créer/ouvrir/sauver), export dot/png, quit (callback réutilisé par SIGINT).
- `gui_toolbar_COMPONENTS.ml` — palette verticale des composants ; instancie les menus Add/Properties/Remove/Startup/Stop de chaque composant.
- `gui_toolbar_COMPONENTS_layouts.ml/.mli` — layouts génériques (foncteurs paramétrés par `Toolbar_entry`, `Add`…) factorisant les menus de composants.
- `gui_toolbar_DOT_TUNING.ml` — barre de réglage du dessin (zoom, nodesep, splines…), branchée réactivement (Cortex) sur `sketch`.
- `gui_dialog_A_PROPOS.ml` — dialogue « À propos ».
- `gui_dialog_toolkit.ml` — petit foncteur utilitaire (labels/tooltips markup d'un dialogue glade).
- `gui_source_editing.ml` — éditeur GtkSourceView (config vde_switch, zebra…), langages par id/mime.
- `menu_factory.ml/.mli` — fabrique générique de menus ; `.mli` injecté par `INCLUDE DEFINITIONS`.
- `simple_dialogs.ml` — dialogues messages (info/warning/error/confirm) prêts à l'emploi.
- `talking.ml/.mli` — messages d'aide/erreur à l'utilisateur (`Msg.help_*`) ; embarque `can-directory-host-sparse-files.sh` par `include_as_string_p4`.
- `ledgrid.ml` — widget custom « grille de LEDs » (flash/blink par timeouts GMain) ; main de démo inactif en fin de fichier.
- `ledgrid_manager.ml` — serveur de fenêtres ledgrid piloté par socket datagramme depuis les vde_switch patchés ; thread dédié.

## Non-code
- `gui_glade3.xml` — SOURCE DE VÉRITÉ de l'interface (glade, `make edit-gui`).
- `gui.xml` + `glade-2.0.dtd` — `?` interface glade-2 héritée, plus référencée (vestige apparent, non confirmé).
- `gui_component-node-{with,without}-state.ml-template` — `?` gabarits d'ajout de composant, citent un `gui_machine.ml` disparu (vestiges apparents, non confirmés).
- `Makefile` — une cible : `edit-gui` (lance glade).
