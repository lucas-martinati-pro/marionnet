---
name: marionnet-composants
description: Ajouter ou modifier un composant réseau de Marionnet (machine, router, hub, switch, cable, cloud, world_bridge, world_gateway) — patron user_level + simulation_level + dialogue where_p4, treeviews, pièges de typage. Charger quand le chantier touche bin/{machine,router,hub,switch,cable,cloud,world_*}.ml, user_level ou simulation_level.
---

# Composants réseau Marionnet

## Patron d'un composant (un fichier unique)

Chaque composant vit dans UN fichier `bin/<nom>.ml` contenant, dans cet ordre logique :
la classe **user-level** (hérite des classes de `user_level.ml`), la classe
**simulation-level** (hérite de `process`/descendants de `simulation_level.ml`), et le
dialogue GTK d'ajout/édition (`module Dialog_…`) **rejeté en fin de fichier** par la clause
`where` (extension camlp4 `where_p4`, chargée par `#load` en tête de fichier).

1. Pars d'un composant existant proche (`hub.ml` pour un équipement vde simple,
   `machine.ml` pour un équipement UML complet) — PAS des `.ml-template` de bin/gui/
   (vestiges apparents, ils citent une organisation disparue).
2. Construis le dialogue avec `gui_bricks` (form, spins, combos, entrées IP) ; branche le
   menu du composant via les foncteurs de `gui_toolbar_COMPONENTS_layouts`.
3. Enregistre l'équipement dans la palette (`gui_toolbar_COMPONENTS.ml`) et vérifie la
   (dé)sérialisation Xforest (méthodes `to_forest`/`eval_forest_*` côté user_level).
4. Icônes : `bin/images/` (états on/off/pause, 4 tailles) — la section install de `bin/dune`
   les embarque par glob.

## Règles

- Ne touche jamais `bin/main.ml` (vestige), `version.ml`/`meta.ml` (générés).
- Les casts user↔simulation utilisent `Obj.magic` : n'en AJOUTE pas ; si tu modifies un
  passage qui en contient, réduis-les si c'est local et sûr (dette à résorber à l'occasion).
- Toute opération réseau passe par `task_runner` (sérialisation) ; tout accès GUI depuis un
  thread non-GTK passe par `gMain_actor`.
- `.mli` : seulement si le module est de nature « bibliothèque » (les composants n'en ont pas).
- Chaînes utilisateur : entoure de `s_`/`f_` (gettext) ; l'extraction POT est une cible make
  (`gettext-all-ml-pot-files`), pas dune.
- Persistance par projet : états dans les treeviews (`treeview_ifconfig`, `treeview_defects`…),
  fichiers COW via `cow_files` dans `states/`.

## Vérification

Builde avec `make` (JAMAIS `dune build` seul sur clone frais). Teste : ajout du composant
via la palette, démarrage/arrêt (surveille la console : `death_monitor` signale les morts
inattendues), sauvegarde puis réouverture du projet (round-trip Xforest), export du dessin.

Référence : `docs/ARCHITECTURE.md` § 2, 4, 5 ; rôles des fichiers : `bin/CLAUDE-file-overview.md`.
