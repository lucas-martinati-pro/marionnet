---
name: marionnet-gui
description: Chantier GUI de Marionnet — édition de gui_glade3.xml, piège gui.ml (généré-puis-modifié), foncteurs de complétion Make(State), discipline threads GTK (gMain_actor), dialogues gui_bricks. Charger pour toute modification de bin/gui/, bin/gui.ml, ou de l'interface GTK en général.
---

# GUI Marionnet (lablgtk3 + glade)

## Le piège central : gui.ml

`bin/gui_glade3.xml` (dans bin/gui/) est la **source de vérité** de l'interface ; édite-la
avec `make edit-gui` (glade). `bin/gui.ml` (accès typés aux widgets) a été généré par
lablgladecc **puis modifié à la main** : ne relance JAMAIS lablgladecc pour le remplacer
(aucune procédure de régénération n'est établie). Quand le xml change, reporte les
changements **à la main** dans `gui.ml` (nouvelles classes/casts d'accès aux widgets).

## Patrons à suivre

- Complétion par **foncteurs** : un nouvel écran/menu suit le patron
  `Make (State : sig val st : State.globalState end)` appliqué dans `bin/marionnet.ml` —
  jamais de référence globale croisée à l'état.
- Dialogues : construis avec `gui_bricks` (form, spin/combo/IP, yes_or_cancel) ; messages
  simples via `simple_dialogs` ; textes d'aide dans `talking.ml`.
- Menus de composants : passe par les foncteurs de `gui_toolbar_COMPONENTS_layouts`
  (workaround lablgtk : `~label:""` obligatoire dans `GMenu.image_menu_item`).
- Widgets glade nommés en MAJUSCULES suffixées (`window_MARIONNET`, `toolbar_COMPONENTS`).

## Discipline threads (non négociable)

GTK vit dans le SEUL thread principal (`GtkThread.main`). Depuis tout autre thread, poste
l'action via `gMain_actor` (il gère le cas « je suis déjà le thread GTK » sans deadlock).
Pour les animations/timeouts, utilise GMain (Idle/Timeout), pas des threads.

## Règles

- Chaînes utilisateur : `s_`/`f_` (gettext).
- `bin/gui/gui.xml` (glade-2) et les `.ml-template` sont des vestiges apparents : ne t'en
  inspire pas sans vérification.
- `.mli` seulement pour les modules « bibliothèque » (gui_bricks, menu_factory, talking en
  ont ; les écrans n'en ont pas). `menu_factory.mli` est injecté par `INCLUDE DEFINITIONS`
  (chemin `../../../../` fragile — ne pas déplacer le fichier sans l'ajuster).

## Vérification

Builde par `make`, lance l'application (`make run` ou le binaire), et exerce le flux modifié
à l'écran — le typecheck ne prouve rien pour du GTK (casts dynamiques dans gui.ml).

Référence : `docs/ARCHITECTURE.md` § 3, 5 ; rôles : `bin/gui/CLAUDE-file-overview.md`.
