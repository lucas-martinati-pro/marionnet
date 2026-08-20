# `driven-sessions/` — bancs rejouables, versionnés

Un *driven session* est une session de Marionnet **pilotée** plutôt que cliquée : le mot est
celui du dépôt (`bin/gui/gui_menubar_MARIONNET.ml`, `bin/script_mode.ml`), et c'est ce que fait
l'option `--control-socket`. Les scripts rassemblés ici en jouent une, ou en refusent une, pour
**prouver un comportement** — pas pour tester une unité de code (les tests unitaires OCaml vivent
sous `dune test`).

## Ce qui a le droit d'être ici

Un banc n'est versionné que s'il est **déterministe et exécutable partout** :

- **pas d'invité qui boote** (pas de noyau UML, pas de rootfs, pas de minutes d'attente) ;
- **pas de `sudo`**, donc pas de bridge, pas de tap, pas de `iptables` ;
- **pas de plateforme absente** : ce qui manque se **saute** (code 77), jamais ne se maquille en
  succès.

Tout le reste — un bail DHCP dans un invité, une carte physique, un patch témoin recompilé — est
un **banc jetable** : il se joue à la main et sa sortie va au journal du chantier concerné.
Le critère vient de `docs/todo-transverse.md` § 3.6.

## Convention

- Un fichier `<sujet>.sh` par comportement prouvé, exécutable, sans argument obligatoire ;
  argument optionnel : le chemin du binaire à éprouver (défaut : `_build/default/bin/marionnet.exe`).
- **Codes de sortie** : `0` = PASS, `77` = SKIP (rien de significatif n'a pu être joué),
  toute autre valeur = FAIL.
- Chaque cas s'annonce sur une ligne `PASS:` / `FAIL:` / `SKIP:`, et le script finit par un
  décompte.
- Un banc **nettoie derrière lui** (processus lancés, socket, répertoire temporaire). Rappel
  utile : le `quit` du canal ne passe pas par `close_project`, donc une session qui a **ouvert un
  projet** laisse son `/tmp/marionnet-<n>.dir/` (mesuré à l'ép. 1 ; une session sans projet, elle,
  ne laisse rien).
- Un banc doit **échouer** sur le code d'avant le correctif qu'il prouve. Un banc qui passe des
  deux côtés ne prouve rien : la mesure rouge/vert est consignée dans le journal du chantier.

## Les bancs

| Banc | Prouve | Épisode |
|---|---|---|
| `control-socket-refusal.sh` | `--control-socket` : refus de démarrer quand le canal ne peut pas être servi (chemin non absolu, chemin plus long que `sun_path`, répertoire non inscriptible), et non-régression du chemin nominal | `marionnet-todo-transverse` ép. 2 |
| `add-rollback-on-constructor-failure.sh` | `add` : un composant refusé par son propre constructeur (`--ports=0`, `--ports=99`) ne laisse rien — ni dans `ls`, ni sur son nom — et un `add` légitime marche toujours | `marionnet-todo-transverse` ép. 3 |
