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
  succès. Un serveur X en fait partie : un banc qui mesure une **fenêtre** a besoin d'un
  affichage — démarrer la GUI n'est ni un invité ni un privilège, donc le banc est versionné, et
  il se saute entier sur une machine sans écran.

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
| `add-ports-bounds.sh` | `add … --ports=N` : les bornes sont celles de la nature (machine 1-8, hub 4-16…), vérifiées **avant** la construction, et `add` refuse dans les mêmes mots que `set … port_no` | `marionnet-todo-transverse` ép. 4 |
| `set-distrib-unknown.sh` | `set … distrib` et `add … --distrib=` : un filesystem non installé est **refusé** (avec la liste de ceux qui le sont) au lieu d'être remplacé en silence ; une bascule légitime passe toujours | `marionnet-todo-transverse` ép. 5 |
| `set-variant-unknown.sh` | `set … variant` et `add … --variant=` : une variante qui n'existe pas pour le filesystem du composant est **refusée** (avec la liste de celles qui existent) au lieu d'être avalée ; un `set distrib` qui ferait perdre la variante portée est refusé aussi, et le chemin de sortie (`variant aucune`) fonctionne. Seul banc à jouer **deux sessions** et à détourner `HOME` : il **fabrique** la variante dont il a besoin | `marionnet-todo-transverse` ép. 7 |
| `default-kernel-needs-no-remap.sh` | Le noyau qu'un composant reçoit **à sa création** est déjà celui que cet hôte peut faire tourner : enregistrer le projet et le relire ne l'ajuste pas (y compris pour un `.mar` ne portant **aucun** attribut `kernel`), tandis qu'un `.mar` nommant vraiment un noyau inutilisable est, lui, toujours réparé. Le banc ne connaît aucune règle de choix : il compare ce que le constructeur a décidé à ce que `remap_obsolete_kernel_at_import` en dit au chargement suivant | `marionnet-todo-transverse` ép. 12 |
| `switch-rc-after-poweroff.sh` | `rc-set` sur un **switch** : le rc joué est celui du démarrage courant, pas celui figé au premier — et un rc activé après un démarrage sans rc est joué lui aussi. Le seul banc à **démarrer** des composants (un switch n'a ni invité ni privilège : `vde_switch` suffit), et à lire le journal `rc_config` plutôt que le modèle | `marionnet-todo-transverse` ép. 11 |
| `message-window-geometry.sh` | La fenêtre d'un message (`Simple_dialogs.error / warning / info / help`) reste lisible et **fermable** quelle que soit la longueur du texte : ni colonne étroite, ni fenêtre plus haute que l'écran. Le banc mesure la **vraie** fenêtre de la **vraie** application (X server), sans un seul clic : l'avertissement de démarrage de l'ép. 6 **nomme** le répertoire temporaire, donc la profondeur de ce répertoire choisit la longueur du message | `marionnet-todo-transverse` ép. 13 |
