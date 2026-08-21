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
- **Une session lancée par un banc se termine par le canal (`quit`) ou par `SIGKILL`.** Marionnet
  **neutralise SIGTERM** délibérément (`bin/marionnet.ml` : un `halt` dans un invité en envoie
  un), donc un `kill` suivi d'un `wait` **ne rend jamais la main** — mesuré à l'ép. 18.
- **Un banc qui matche un texte de l'application fige la langue** (`LANGUAGE=C LC_ALL=C` au
  lancement). Depuis l'ép. 15, un binaire de `_build` lit les catalogues du dépôt : un motif
  anglais ne matche plus rien sous locale française, et un banc qui cherche une **absence** ne
  s'en aperçoit pas — il passe en ne prouvant plus rien (mesuré sur
  `default-kernel-needs-no-remap.sh`, dont 2 cas sur 3 étaient devenus vides).

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
| `save-entries-greyed-while-running.sh` | Les trois entrées qui écrivent le projet (« Enregistrer », « Enregistrer sous », « Copier vers ») sont sensibles **exactement** quand le projet est ouvert et que rien ne tourne : rien avant qu'un projet existe, insensibles dès qu'un switch démarre, sensibles de nouveau une fois tout éteint. Le banc lit la réaction dans le journal de l'application (`--debug`) — la condition calculée **et** le nombre de widgets auxquels elle s'applique, qui dit qu'aucune entrée n'a été oubliée ni ajoutée. Il ne lit pas le pixel : une application lablgtk3 ne s'enregistre pas sur le bus AT-SPI (mesuré) | `marionnet-todo-transverse` ép. 14 |
| `gettext-catalogue-in-dev-tree.sh` | Un binaire lancé depuis `_build` lit les catalogues **du dépôt** : le `.mo` réellement ouvert (lu dans les `openat` de l'application, pas dans ce que le code croit) est celui de l'arbre de développement et non celui d'un autre Marionnet installé sous `/usr` ; un `MARIONNET_LOCALEPREFIX` explicite l'emporte sur cette découverte, **lien symbolique compris** — c'est la disposition que dune donne à son site `locale` ; et le journal `--debug` nomme le répertoire retenu **et** son origine | `marionnet-todo-transverse` ép. 15 |
| `import-warning-outside-import.sh` | Un avertissement d'import ne naît **que** d'un import : une écriture explicite (`set … variant aucune` sur un routeur) n'en dépose plus, et le chargement suivant d'un projet qui n'a rien à adapter n'affiche **aucun** récapitulatif — tandis qu'un `.mar` nommant vraiment un noyau inutilisable, fabriqué par le banc, est toujours adapté **et** récapitulé. Le banc lit le récapitulatif dans le champ `notifications` de la réponse d'`open`, donc sans clic ni `xdotool` | `marionnet-todo-transverse` ép. 17 |
| `quit-is-observable.sh` | La fin d'une session est observable **par le canal seul** : `quit` (et `status`) publient le **pid** de la session, et attendre ce pid suffit — alors que la réponse de `quit`, elle, précède la mort du processus d'environ une demi-seconde (mesuré). Le banc mesure aussi ce qui **justifie** ce choix : le fichier socket disparaît après une sortie propre mais **survit** à un `SIGKILL`, donc son absence prouve une fin et sa présence ne prouve rien ; et un `quit` **refusé** (mode examen) ne promet aucune fin. Le seul banc à lire une réponse par un **coprocess** : `socat` ne rend la main qu'à la fermeture de la connexion, c'est-à-dire à la mort du processus — précisément ce qu'il s'agit de mesurer | `marionnet-todo-transverse` ép. 18 |
| `run-directories-recover-and-purge.sh` | Les répertoires de session abandonnés peuvent être **récupérés** avant d'être supprimés, et la suppression peut être demandée par le Marionnet qui tourne : `--archive-dirs` écrit un `.mar` par répertoire (racine = le répertoire de projet, `tmp/` exclu — la commande de `save_project`) et n'efface **rien**, tandis que `--caller-marionnet` ne lève le refus de purger que pour ce pid-là, vérifié vivant et vraiment Marionnet, tout **autre** Marionnet l'interdisant toujours. Les deux cas qui exigent une session vivante se sautent sans affichage | hors chantier (2026-08-21), suite de `marionnet-todo-transverse` ép. 6 |
