# Chantier : journalisation-profonde

> Chantier long, ouvert le 2026-08-10. Cible : **pousser la journalisation au-delà de
> Marionnet, jusqu'à l'intérieur des UML (machines, routeurs) et jusqu'à l'intérieur des
> switchs**, sous une forme qu'un script — donc un agent — peut lire. Chantier frère de
> `pilotage-par-script`, qui lui sert de canal de lecture sans le posséder. Skill de
> pilotage : `chantier-long`.

## 1. Contexte et objectif

Le canal de pilotage par script (`docs/pilotage-par-script.md`, clôturable) sait **agir** sur un
réseau simulé : créer un composant, le câbler, le configurer, le démarrer, attendre qu'il soit
prêt. Il ne sait pas **voir**. Tout s'arrête à la frontière de l'hôte : ce qui se passe *dans* une
machine UML, *dans* un routeur ou *dans* un switch n'est observable que par un humain assis devant
un xterm.

Cette asymétrie se paie dans trois situations concrètes :

1. **Valider une image.** `kernel-rootfs-refresh` doit répondre à « tous les services démarrent-ils
   au boot ? », « ce binaire est-il dans la bonne version ? ». Aujourd'hui : ouvrir un xterm et
   regarder.
2. **Vérifier un scénario.** Un `.mrn` pose des configurations dans des machines et des routeurs
   (`rc-set`, ép. 4e du canal). Rien ne dit si elles se sont **appliquées**. Un `rc_config` qui
   échoue échoue en silence.
3. **Concevoir un TP par agent.** Un enseignant demandera à un agent de composer un TP réseau avec
   des configurations précises. Sans journal, l'agent ne peut pas contrôler son propre livrable.

### Ce que l'option `-d` fait — et pourquoi ce n'est pas un système de journalisation

Vérifié dans `bin/initialization.ml`, module `Debug_level` : un **booléen global**, à trois effets.

1. Côté hôte, `redirection ()` rend `" 1>/dev/null 2>/dev/null "` hors debug, `""` en debug — donc
   sans `-d`, toute commande shell lancée par Marionnet est muette par construction.
2. Il ouvre les `Log.printf` de Marionnet **et** d'ocamlbricks (`Log.Tuning.Set.debug_level`).
3. Il passe `debug_mode=true` sur la ligne de commande noyau (`simulation_level.ml:902`), que le
   relais invité traduit en `set -x` (`uml/guest/marionnet-relay:46-48`).

La trace part donc **dans un xterm** — le mode debug force `console = "xterm"`
(`simulation_level.ml:854-863`) — et meurt avec lui. Rien n'est **par composant**, rien n'est
**fichier**, rien n'est **relisable par un script**, et rien ne **survit** au projet. L'analogie de
départ (« faire comme `-d` ») désigne donc la bonne *intention* — instrumenter le lancement — mais
pas le bon *support*.

## 2. Ce qui a été mesuré (sondes de l'épisode 0)

Ces quatre constats sont **mesurés**, pas déduits d'une lecture. Ils fondent les décisions du § 3.

### 2.1 Deux emplacements libres existent déjà côté invité, sans reconstruire une seule image

Le relais invité termine son `start()` par :

```bash
for i in /mnt/hostfs/{$virtualfs_name.,marionnet-}relay*; do
  echo "Source-ing $i ..." ; source "$i";
done                                     # uml/guest/marionnet-relay:472-475
```

Glob rejoué en bash : l'ordre est `<image>.relay*` d'abord, puis `marionnet-relay*` **en ordre
alphabétique**. Donc un fichier `marionnet-relay.00-journal` est sourcé **avant** le
`marionnet-relay.rcfile` de l'utilisateur, et un `marionnet-relay.zz-collect` **après**. Or
`make_hostfs_content` (`simulation_level.ml:1235-1252`) écrit déjà dans ce répertoire — c'est par
là que transitent le `.rcfile` et `boot_parameters`.

**Conséquence décisive : un prologue et un épilogue peuvent être injectés par l'hôte, sans toucher
au relais, donc sans reconstruire aucune image, donc sur les vieilles images aussi.**

Constat annexe, sans rapport avec le chantier mais noté ici : `nullglob` est **off**. Quand
l'image n'a pas de `<image>.relay`, la boucle source le motif littéral et affiche une erreur à
chaque boot. Bénin, et hors de portée sans rebuild.

### 2.2 Le rcfile arrive trop tard pour couvrir tout le boot

Le relais est un script d'init (`# Required-Start: $local_fs $network $syslog`). Noyau, `init` et
services le précèdent : un `set -x` dans le rcfile ne les verra jamais. Deux sources possibles pour
ce qui précède — une collecte *a posteriori* (`dmesg`, `journalctl -b`) et la **console UML**.

### 2.3 Le switch est le mieux instrumenté des trois, et personne ne l'écoute

Marionnet crée **inconditionnellement** une socket de management par switch
(`switch.ml:604`, `~management_socket:()` — les hubs n'en ont pas) et s'en sert déjà pour compter
les ports actifs avant de brancher les câbles internes.

Interrogée sur un `vde_switch 2.3.2` réel, cette socket expose :

| Commande | Ce qu'elle rend |
|---|---|
| `port/print`, `port/allprint` | table ports/endpoints — qui est branché où |
| `hash/print`, `hash/find MAC` | **table d'apprentissage MAC** — ce que le switch a réellement appris |
| `fstp/print`, `fstp/showinfo` | état du spanning tree |
| `debug/list`, `debug/add <cat>` | **11 catégories d'événements diffusables en continu** : `hash/+`, `hash/-`, `port/+`, `port/-`, `port/descr`, `port/ep/+`, `port/ep/-`, `fstp/status`, `fstp/root`, `fstp/+`, `fstp/-` |

C'est exactement la matière d'un TP de réseau. Et le défaut réel est là : l'option `--rcfile` de
`vde_switch` est **morte** — le code le dit lui-même, `switch.ml:593` :
*« Unused: vde_switch doesn't interpret correctly commands provided in this way! »*. Le rc du
switch part donc par la socket, via `send_commands_to_vde_switch_ignoring_answers` — **en jetant
les réponses**. Une configuration VLAN fautive échoue aujourd'hui en silence total.

### 2.4 Le mode examen fait déjà la moitié du travail, et l'autre moitié est morte

À l'extinction propre, si Marionnet tourne en `--exam`, il importe des fichiers du hostfs dans le
treeview `documents` — donc dans le `.mar`, donc consultable en GUI et rejouable. Une **machine**
importe `<hostfs>/report.html` **et** `<hostfs>/bash_history.text` (`machine.ml:761-775`) ; un
**routeur**, seulement `report.html` (`router.ml:1283-1291`) — asymétrie à trancher à l'ép. 7, un
routeur ayant lui aussi un historique de shell.

**Le consommateur est vivant et versionné. Le producteur n'existe pas.** `grep` sur tout le dépôt
ne trouve ces deux noms que dans le code qui les *lit* ; les seules occurrences de `bash_history`
sous `uml/` sont des lignes qui **vident** ce fichier à la fabrication de l'image
(`pupisto.common/toolkit_chroot.sh:255`, `pupisto.debian.sh:1163`). Le mode examen importe
aujourd'hui des fichiers que personne n'écrit.

Ce chantier ne crée donc pas une destination durable : il **rend un producteur** à une destination
qui attend depuis longtemps.

> **Corrigé à l'épisode 7** (2026-08-11), qui a mesuré ce paragraphe : le consommateur était
> vivant, mais **pas fonctionnel**. `import_file` lève sur un fichier absent, en ouvrant un
> dialogue d'erreur — l'extinction d'une machine en mode examen produisait donc une exception, pas
> un import. L'asymétrie machine/routeur est tranchée du même coup (un seul geste pour les deux,
> § 4.7), et le nom `report.html` est remplacé par `report.md`.

## 3. Décisions

Prises avec l'auteur le 2026-08-10, après interrogatoire (`grill`) et sous l'échelle `lazy-senior`.

| # | Décision | Motif |
|---|---|---|
| **D1** | La plomberie invité est **injectée par l'hôte dans le hostfs**, pas ajoutée au relais | le glob du § 2.1 la source déjà, dans le bon ordre ; aucune image ne bouge ; marche sur les vieilles images ; **aucune dépendance envers `kernel-rootfs-refresh`** |
| **D2** | On remonte jusqu'à la **console UML**, en plus de l'épilogue collecteur | seul moyen de voir un boot qui n'atteint jamais le relais (panique noyau, `init` cassé) — précisément le cas que `kernel-rootfs-refresh` veut diagnostiquer. **Et** seule source hors de portée de l'invité : le hostfs est inscriptible par l'étudiant, qui peut y effacer ou falsifier un journal ; une capture faite côté hôte, non. C'est ce qui rend une notation défendable |
| **D3** | **Deux supports, deux usages.** hostfs = journal *vivant* (écrasé à chaque boot, lu à chaud) ; treeview `documents` = *archive* importée à l'extinction, persistée dans le `.mar` | l'import n'a lieu qu'à l'extinction propre : tout mettre dans `documents` tuerait l'usage « vérifier mon `.mrn` **pendant** qu'il tourne ». Réanime au passage le mécanisme du § 2.4 |
| **D4** | Switch : d'abord **ne plus jeter les réponses du rc**, puis **instantané à la demande** (`port/print`, `hash/print`, `fstp/print`). Le flux `debug/add` reste **en réserve** | le premier point est un **défaut**, pas une fonctionnalité. Le second répond à la question d'un TP (« la MAC de `m1` est-elle apprise sur le bon port ? ») sans thread permanent, sans fichier à borner, sans cycle de vie à accrocher. Le flux ne se justifiera que pour une question **temporelle** (convergence du spanning tree) |
| **D5** | **Collecteur toujours actif ; enregistrement de console sur option** (implicite en `--exam`) | un agent qui vérifie son `.mrn` doit trouver le journal **sans connaître de drapeau**. Enregistrer une session en silence hors examen serait de la surveillance, pas du diagnostic. Et : **aucun attribut persisté ajouté**, le format `.mar` v3 tout juste stabilisé ne bouge pas |
| **D6** | Le chantier livre la **matière** et des **exemples exécutables** joués par un banc. Un vérificateur à l'exécution et un skill de conception de TP sont **inscrits comme épisodes optionnels de fin** | motif de l'ép. 8 de `pilotage-par-script` : le premier run du banc y a attrapé **6 affirmations fausses** écrites de bonne foi après lecture du source. Et on ne conçoit pas une couche de verdict avant qu'un journal ait tourné une seule fois |
| **D7** | **Nouveau chantier**, pas un épisode 13 de `pilotage-par-script` | ce dernier est clôturable, son § 9 est soldé, aucun défaut ouvert. Le périmètre est ailleurs : `uml/`, mode examen, `treeview_documents`, socket vde, arguments de console. Le canal de script est ici **consommateur**, pas sujet — exactement le rapport qu'avait l'ép. 4e avec le mécanisme `rc_config`, qu'il publiait sans le posséder |

### 3.1 Mécanisme d'encadrement retenu (à valider à l'épisode 1)

Prologue et épilogue sont sourcés **dans le shell du relais** : une redirection `exec` posée par le
prologue fuirait sur toute la fin du boot (`clear`, `linuxlogo`, l'affichage de la console). D'où
l'encadrement :

- le **prologue** (`marionnet-relay.00-journal`) sauve les descripteurs (`exec 3>&1 4>&2`) et
  redirige vers un `tee` qui écrit **à la fois** dans `/mnt/hostfs/rc_config.log` et sur la console
  — l'étudiant continue de voir son boot ;
- l'**épilogue** (`marionnet-relay.zz-collect`) restaure les descripteurs, clôt le `tee`, puis
  collecte.

L'ordre du glob donne cet encadrement gratuitement. Deux points à vérifier à l'ép. 1 : la survie du
`tee` en *process substitution* (le relais est bien bash), et l'éventuelle dépendance du tri du glob
à la locale de l'invité.

## 4. Structure en épisodes

| Ép. | Livrable | Discriminant (la preuve qui départage) |
|---|---|---|
| **0** | Officialisation : cette doc, fiche mémoire, pointeurs | — (aucun code) |
| **1** | **Prologue injecté** : `marionnet-relay.00-journal` déposé par `make_hostfs_content` ; auto-espionnage du `rc_config` (`set -x`, sortie **et** erreur) vers `/mnt/hostfs/rc_config.log`. **Livre aussi son épilogue de fermeture** `marionnet-relay.zz-journal` (cf. § 4.1) | machine trixie démarrée **par le canal**, `rc_config` volontairement fautif : le journal côté hôte porte la trace et le code d'erreur, là où **rien** n'apparaît aujourd'hui — **fait** (2026-08-10) |
| **2** | **Épilogue collecteur** : la collecte se greffe **à la fin de `marionnet-relay.zz-journal`** (le nom `zz-collect` de l'ép. 0 est caduc : un second fichier en `zz-c…` serait sourcé *avant* le `zz-j…`, donc *dans* la fenêtre de capture) — `dmesg` et, selon `init_system` (déjà connu de Marionnet, `simulation_level.ml:826`), `journalctl -b` + `systemctl --failed`, sinon un extrait de `/var/log/` (cf. § 4.2) | un `systemctl --failed` non vide devient visible côté hôte **sans ouvrir un xterm** ; **et** le même scénario sur une image sysv produit l'équivalent sans erreur — **fait** (2026-08-10) |
| **3** | **Le canal lit** : verbe `log` dans `control_server.ml`, publié par `help` (5ᵉ application de la règle d'unicité) — **deux** journaux à servir, pas un (cf. § 4.3) | `mrnctl log m1 --tail=20` rend ce que `tail` rend côté hôte ; un nœud sans hostfs reçoit un `bad_argument`, par symétrie avec `wait --ready` — **fait** (2026-08-11) |
| **4** | **Switch : ne plus jeter les réponses** du rc (`send_commands_to_vde_switch_ignoring_answers`). Le journal est écrit **par Marionnet**, dans le répertoire de travail du projet, et servi par le verbe `log` de l'ép. 3 (cf. § 4.4) | un rc de switch avec une commande VLAN fautive produit une erreur **lisible**, là où il ne produit rien — **fait** (2026-08-11) |
| **5** | **Switch : instantané** par la socket mgmt, rendu en JSON — quatre tables et non trois, `vlan/print` ayant rejoint `port/print`, `hash/print` et `fstp/print` (cf. § 4.5) | la MAC d'une machine réellement démarrée apparaît dans la table du switch auquel elle est câblée — **et pas** dans celle d'un autre — **fait** (2026-08-11) |
| **6** | **Capture de console** (option `--console-log`, implicite en `--exam`) : la sortie du processus UML est enregistrée dans `<projet>/<nom>-console.log`, servie par le verbe `log` sous le nom `console` (cf. § 4.6). Des trois pistes, `fd:` — et encore, seulement là où un `console=` explicite éteint la console par défaut | un démarrage qui n'atteint **jamais** le relais (courant coupé en plein boot) laisse une trace côté hôte, là où le hostfs reste **vide** — **fait** (2026-08-11) |
| **7** | **Réanimer le mode examen** : le prologue pose l'historique **horodaté** dans le hostfs (`bash_history.text`, 4ᵉ journal du verbe `log` sous le nom `commands`), l'épilogue accroche à l'**arrêt** un producteur de rapport **Markdown** (`report.md`, section pare-feu comprise), et l'import du § 2.4 — enfin gardé, enfin symétrique — archive rapport, historique **et** console (cf. § 4.7) | après extinction propre en `--exam`, le treeview `documents` porte les entrées **et** elles survivent à un cycle sauvegarde/rechargement du `.mar` — **fait** (2026-08-11) |
| **8** | **Le terminal de l'étudiant, enregistré** (option `--terminal-log`, implicite en `--exam`) : Marionnet substitue son enregistreur au premier champ de `xterm=` et `script(1)` capture ce qui traverse la fenêtre ; 5ᵉ journal du verbe `log`, nommé `terminal`, archivé **nettoyé** dans `documents` (cf. § 4.8) | un témoin écrit sur `/dev/tty0` apparaît dans `log … terminal` et **pas** dans `log … console` — **fait** (2026-08-12) |
| **9** | **Documentation + exemples exécutables + banc** : § 11 neuf du guide `doc-src/scripting/` (les cinq journaux, leurs deux natures, `switch-info` en miroir), note utilisateur `doc-src/exam-mode.md` pour l'enseignant, et deux exemples versionnés — `04-journals.sh`, `05-exam-session.sh` (cf. § 4.9) | les exemples de la doc sont joués **tels quels** par le banc, et le tableau des journaux du guide est **comparé** à ce que `help` publie — **fait** (2026-08-12) |
| **10** | **Lire un rapport Markdown depuis la GUI** : un `.md` s'ouvre aujourd'hui dans `MARIONNET_TEXT_EDITOR` ; il lui faut un vrai geste de lecture (conversion vers HTML par un convertisseur présent puis navigateur, ou lecteur dédié avec repli) | un double-clic sur le rapport d'un composant, dans le treeview `documents`, le donne à lire **rendu** |
| **11** *(opt.)* | Vérificateur à l'exécution : assertions déclaratives, compagnon de `mrn-check` | à concevoir seulement une fois 1→9 opérationnels |
| **12** *(opt.)* | Skill de conception/vérification de TP pour agent | idem |

### 4.1 Ce que l'épisode 1 a réellement livré (et pourquoi deux fichiers, pas un)

Le § 3.1 avait prévu l'encadrement ; l'implémentation a montré qu'il n'est **pas sécable**. Livrer
le prologue seul aurait laissé la redirection courir sur toute la fin du boot — `clear`,
`linuxlogo`, la bannière de console seraient partis dans le journal, et la console de l'étudiant se
serait tue. L'épisode 1 livre donc **le prologue et l'épilogue**, ce dernier réduit à sa fonction de
**fermeture** ; l'épisode 2 lui ajoutera la collecte, au même endroit, sans toucher au prologue.

| Fichier | Où il vit | Ce qu'il fait |
|---|---|---|
| `bin/scripts/marionnet-relay.00-journal.sh` | versionné, **embarqué** dans le binaire | sauve l'état (`xtrace`, `errtrace`, `PS4`, trap `ERR`, descripteurs 1 et 2 rangés en 3 et 4), tronque `/mnt/hostfs/rc_config.log`, capture vers un `tee`, pose `PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '`, `set -x` et un trap `ERR` |
| `bin/scripts/marionnet-relay.zz-journal.sh` | idem | rend l'état, referme la capture, **attend** le `tee` |

Quatre points que la conception laissait ouverts, tranchés par la mesure :

- **le `tee` en substitution de processus survit** dans l'invité (trixie, bash 5.2) ; le repli sans
  `tee` (`exec >>` direct) reste écrit pour les images qui n'en auraient pas, et le mode retenu est
  **annoncé dans l'en-tête du journal** ;
- **l'ordre du glob ne dépend pas de la locale** — rejoué sous `C` et sous une locale UTF-8 ;
- **le statut d'échec exige un trap `ERR`** : un fichier *sourcé* n'avorte pas, et le `$?` que
  l'épilogue verrait est celui du `echo "Source-ing …"` de la boucle du relais, pas celui du
  `rc_config`. Le trap suspend la trace le temps d'écrire `!! FAILED (status N): <commande>`, sans
  quoi le journal se documente lui-même plutôt que la panne ;
- **`dune` ne voit pas à travers camlp4.** `INCLUDE_AS_STRING` lit le `.sh` à la préprocession, mais
  la dépendance n'existe pour dune que si elle est **déclarée** : sans elle, éditer un script
  laissait le binaire porter **silencieusement** la version précédente (constaté sur le premier
  correctif). Les trois scripts embarqués sont désormais dans les `preprocessor_deps` de
  `bin/dune` — y compris `can-directory-host-sparse-files.sh`, qui traînait le même défaut depuis
  toujours.

Le choix de l'embarquement (plutôt qu'un fichier installé) tient en une phrase : un binaire ne peut
pas se désynchroniser des scripts qu'il dépose, et rien de tout ceci ne dépend d'un `make install`.

### 4.2 Ce que l'épisode 2 a livré (et pourquoi un second fichier)

La collecte est greffée **à la fin de l'épilogue**, comme le § 4.1 l'annonçait : le prologue n'a
pas bougé d'une ligne. Elle écrit en revanche dans un **second fichier**,
`/mnt/hostfs/boot.log` :

| Fichier | Répond à |
|---|---|
| `rc_config.log` (ép. 1) | « qu'a fait **mon scénario**, et qu'est-ce qui a échoué dedans ? » |
| `boot.log` (ép. 2) | « cette **image** a-t-elle démarré correctement ? » |

Les fusionner aurait rendu les deux illisibles, et de toute façon la capture du premier est
**close** quand la collecte commence — c'est précisément ce qui garantit que la collecte ne
pollue pas le journal du scénario (le banc le vérifie dans les deux sens).

**Le système d'init est détecté dans l'invité, pas reçu de l'hôte.** La détection est celle de
systemd lui-même (`/run/systemd/system`, `sd_booted(3)`), plus la présence de `journalctl`
puisque c'est ce dont la branche se sert. L'hôte, lui, ne connaît que ce que le `.conf` du
filesystem **déclare** (`INIT_SYSTEM`, `disk.ml#init_system_of`). Les deux figurent dans
l'en-tête — `# init: detected=… declared=…` —, et c'est le seul point de contact OCaml de
l'épisode : **une ligne** dans `boot_parameters` (`simulation_level.ml`). Motif : cette
déclaration sélectionne les `boot_quirks` de la ligne de commande noyau
(`simulation_level.ml:995`) ; un désaccord entre ce que l'hôte croit et ce que l'invité fait
est donc un diagnostic, pas une curiosité.

Trois règles, toutes imposées par le fait que ce code tourne **à la fin d'un boot** :

- **jamais fatale, jamais bruyante** : tout va dans le fichier, rien sur la console que
  l'étudiant regarde — y compris sous `-d`, où l'épilogue vient de remettre `xtrace` (la
  collecte le suspend et le rend) ;
- **jamais illimitée** : `dmesg` et `journalctl` sont tronqués (400 et 500 lignes), les extraits
  de `/var/log` à 200, et chaque commande passe sous `timeout 15` quand l'image a `timeout` ;
- **jamais bloquante** : pas de `systemctl is-system-running --wait`. L'instantané est pris à
  l'heure du relais et **le dit** dans son en-tête : les services démarrés plus tard n'y sont pas.

Quatre mesures ont corrigé le code ou les attentes :

- **une image Marionnet peut n'avoir aucun syslog** (constaté sur `debian-wheezy-08367`) : la
  branche sysv se réduisait alors à `dmesg`, sans dire pourquoi. D'où le listing de `/var/log`,
  **inconditionnel** — une collecte qui dit « il n'y a rien ici » vaut mieux qu'une collecte
  silencieusement vide ;
- **le tampon d'un noyau UML n'a pas toujours sa bannière** « Linux version » : présente sur
  l'invité i686, absente sur le 6.12.95 x86_64, dont le tampon commence par l'échec d'analyse de
  `console_no=1`. Le banc compte donc les **lignes horodatées par le noyau**, pas une bannière ;
- **sous systemd, `journalctl -b` rapporte la sortie du relais** — donc nos propres lignes, trace
  `set -x` et `!! FAILED` comprises. Le témoin de l'épisode 1 (« le journal est le seul fichier
  du hostfs qui garde trace de l'échec ») a dû s'élargir aux **deux** fichiers du chantier ; en
  retour, cela mesure que le prologue enrichit aussi le journal système de l'invité, qui n'aurait
  vu sans lui que le message de `ls`, sans la commande ni son statut ;
- **l'ordre du glob n'est pas le même sur toutes les images** : le relais de wheezy source
  `/mnt/hostfs/{marionnet-,$virtualfs_name.}relay*`, l'inverse du relais actuel. Sans conséquence
  pour nos trois fichiers (tous en `marionnet-`, donc toujours dans l'ordre
  prologue / `.rcfile` / épilogue), mais le `.relay` **propre à l'image** passe après l'épilogue
  là où il passe avant le prologue ailleurs : dans les deux cas il n'est **pas** encadré.

**Mesure** (`journal-bench.sh`, hors dépôt, **60 assertions, 0 échec**), trois invités démarrés
par le canal :

- le **discriminant**, sur trixie : le scénario installe une unit `oneshot` qui échoue, et
  `boot.log` la montre côté hôte dans sa section `systemctl --failed` — sans qu'aucun xterm n'ait
  été ouvert ;
- **l'autre moitié du discriminant**, sur `debian-wheezy-08367` — une image de 2013, sysv, en
  i686 : même collecte, `detected=sysv declared=sysv`, aucune interrogation de systemd, aucune
  erreur. **D1 tient sur les vieilles images** : rien n'a été reconstruit ;
- **D5** : une machine sans le moindre `rc_config` a elle aussi sa collecte, close.

Les deux branches sont en outre rejouées **hors UML**, sur une copie de l'épilogue dont le banc
prouve que le seul écart avec la source est le chemin du hostfs. La branche sysv y est atteinte
par un `PATH` réduit d'où `journalctl` est absent — la détection étant un **et**, c'est la seule
façon de mesurer les deux branches sans dépendre d'une vieille image.

### 4.3 Ce que l'épisode 3 a livré (et pourquoi le verbe ressemble à `rc-get`)

Le canal savait déjà **écrire** dans le hostfs (`rc-set`) et **attendre** un signal qui y est
écrit (`wait --ready`) ; il ne savait pas **lire** ce que l'invité y laisse. Le verbe `log` est le
frère de `wait --ready` — l'un attend le signal, l'autre sert la matière — et il en reprend les
deux traits : le créneau GTK n'achète que la localisation du composant (`find_hostfs`, extraite de
`cmd_wait_ready` et désormais partagée), la lecture se faisant dans le thread appelant, parce
qu'un `stat` ou un `open_in` n'a rien à faire dans la boucle principale.

```
log <component> [<file>|--file=<file>] [--tail=<n>]      file ∈ {rc_config, boot}
```

Quatre choix, et un seul est arbitraire :

- **la forme est celle de `rc-get`** (`[<field>|--field=<field>]`), jusqu'au refus quand les deux
  sont donnés : c'est le même geste — nommer l'une des rares choses qu'un composant garde à côté
  de ses champs — et un client qui sait épeler l'un sait épeler l'autre ;
- **le défaut est `rc_config`** (le seul choix arbitraire) : la première question d'un script est
  ce que **son** scénario a fait ; douter de l'**image** vient après ;
- **deux plafonds, pas un**. Celui des lignes est celui de la réponse : 400 par défaut, l'ordre de
  grandeur que le collecteur s'impose déjà, si bien qu'un `rc_config.log` passe entier et qu'un
  `boot.log` (711 lignes mesurées) est coupé **en le disant** (`truncated`, `total_lines`). Celui
  des octets est celui du **lecteur** : le fichier est écrit par un invité, donc par personne que
  nous contrôlions, et un scénario qui boucle sur une erreur peut le faire grossir sans limite —
  seule la queue est lue (2 Mio), ce qui borne la mémoire de ce thread quoi que l'invité ait fait ;
- **une ligne non-UTF-8 est écartée et comptée** (`dropped_lines`), jamais servie : la réponse est
  une ligne JSON (la raison de `rc_content_is_servable`), et un journal qui perdrait une ligne en
  silence serait pire qu'un journal qui dit combien il n'a pas pu porter.

Les refus disent tous quoi faire ensuite : un switch reçoit le décalque de celui de `wait --ready`
(« aucun système invité, donc aucun hostfs ») ; un fichier pas encore écrit renvoie **vers
`wait --ready`**, parce que c'est le cas normal — le composant n'a pas encore démarré, ou son
invité n'a pas atteint la fin de son boot.

**La 5ᵉ application de la règle d'unicité** ne tient pas à ce que `help` publie la syntaxe (elle le
fait pour tous les verbes) mais à ce qu'il publie **la paire de noms** (`"logs"`), comme il publie
déjà `kinds` et `actions` : la complétion Bash les **demande** au serveur au lieu d'en tenir une
copie. Le piège de l'épisode est là : `--file` appartenait déjà au **client** (`mrnctl -f`, où il
désigne un chemin de l'hôte). Les deux cohabitent — la boucle d'options de `mrnctl` s'arrête au
premier non-option, donc `mrnctl log m1 --file=boot` part bien au serveur — mais la complétion, elle,
devait apprendre à distinguer : chemins partout, journaux après `log`.

**Mesure** (`journal-bench.sh`, **84 assertions, 0 échec**, les trois invités des épisodes
précédents ; `completion-bench.sh`, **53 assertions, 0 échec**). Le discriminant est tenu sur une
trixie **encore allumée** — décision D3, le hostfs est un journal *vivant* : `log m1 --tail=20`
rend, ligne pour ligne, ce que `tail -n 20` rend côté hôte ; sans `--tail`, le fichier entier ;
`log m1 boot` et `log m1 --file=boot` rendent la même chose ; et après `poweroff`, le journal est
toujours servi — il vit dans le hostfs, pas dans le processus.

### 4.4 Ce que l'épisode 4 a livré (et pourquoi le journal d'un switch n'est pas dans un hostfs)

Le défaut tenait en un nom : `send_commands_to_vde_switch_ignoring_answers`. Il lançait un thread
dont l'unique travail était de lire les réponses **pour les jeter**, et cadençait l'envoi par un
`Thread.delay 0.01`. Or **lire la réponse *est* le cadencement** — c'est la preuve que la commande
précédente a été consommée : le délai s'en va avec le rejet, il ne le remplace pas.

**Le protocole a été mesuré, pas lu.** Interrogé avant d'écrire une ligne d'analyseur, un
`vde_switch 2.3.2` réel répond ceci :

```
vde$ 0000 DATA END WITH '.'      <- optionnel : ouvre une réponse qui porte des données
VLAN 0005                        <- ... les lignes de données ...
.                                <- ... closes par un point seul
1000 Success                     <- la ligne de statut : toujours, et toujours en dernier
                                 <- une ligne vide
vde$                             <- l'invite, SANS saut de ligne
```

Codes rencontrés : `1000 Success`, `1022 Invalid argument` (`vlan/create 4999`), `1006 No such
device or address` (un port qui n'existe pas), `1038 Function not implemented` (une commande qui
n'existe pas). Un échec est donc **tout ce qui n'est pas 1000**, et il arrive avec **les mots du
switch** — c'est tout ce que le journal a à porter.

Deux traits de ce protocole condamnent le lecteur booléen que le fichier gardait « currently
unused, but useful for testing » : l'invite n'ayant pas de saut de ligne à elle, elle **préfixe**
la première ligne de la réponse suivante (`vde$ 1000 Success`) — tout se lit modulo ce préfixe ;
et la ligne de statut d'une réponse **qui porte des données** n'est, elle, **pas** préfixée. Un
lecteur qui ne connaît que `"vde$ 1000 Success"` passe donc devant le terminateur de toute
commande qui affiche quelque chose, et avale la réponse d'après. Il a été **supprimé** plutôt que
gardé : un outil de test qui ne peut pas fonctionner en production n'est pas un outil de test.

**Le journal d'un switch ne peut pas vivre dans un hostfs, puisqu'un switch n'a pas d'invité.** Il
est écrit par Marionnet — le seul en position de savoir ce qui est revenu — dans le répertoire de
travail du projet : `<project_working_directory>/<nom>-rc_config.log`. C'est bien un journal
*vivant* au sens de **D3** : il survit à l'extinction du composant (mesuré) et disparaît avec le
projet. Côté modèle, une méthode neuve sur l'ancêtre commun, `rc_journal_file_if_any`, jumelle de
`hostfs_directory_if_any` et **exclusive** d'elle par construction : ou bien un invité écrit son
journal, ou bien c'est nous.

Le verbe `log` de l'épisode 3 n'a donc pas eu besoin d'un frère : il a eu besoin d'une **source**.
`find_hostfs` reste ce qu'il était (et `wait --ready` avec lui, qui doit continuer de refuser sur
un switch : il n'y a rien à attendre) ; `log` interroge désormais `find_journal_source`, à trois
cas — un répertoire (les deux fichiers d'un invité), un fichier (le seul d'un switch), rien du
tout (un hub, un câble). D'où **trois refus qui ne disent pas la même chose**, ce qui est le
critère du chantier depuis l'épisode 3 : un hub s'entend dire que `log` s'applique à une machine,
un routeur **ou un switch** ; un switch à qui l'on demande `boot` s'entend dire qu'il ne boote
pas et qu'il n'a que `rc_config` ; un switch jamais démarré s'entend dire qu'il n'a pas démarré —
**sans** le renvoi vers `wait --ready`, qui n'aurait aucun sens pour lui. Et le champ `available`
de la réponse publie le vocabulaire **de ce composant** (`["rc_config"]` pour un switch), là où
`help` publie celui du canal.

La ligne d'échec est **de la même forme qu'aux épisodes 1 et 2** :

```
> vlan/create 4999
1022 Invalid argument
!! FAILED (status 1022): vlan/create 4999
```

Un seul `grep '^!! FAILED'` répond donc à « qu'est-ce qui a échoué dans mon scénario ? » pour une
machine, un routeur **et** un switch. C'est l'invariant de forme du chantier, et il ne coûte rien.

Deux bornes, imposées par le fait qu'on lit un processus qu'on ne contrôle pas : un **délai de
réception** de 5 s (`SO_RCVTIMEO` sur le descripteur de la connexion) — sans quoi une lecture
bloquante sur un switch qui ne répondra jamais retiendrait ce thread **et** cette connexion pour
toute la vie du projet — et un plafond de 4096 lignes par réponse. Un dépassement est journalisé
et **arrête** l'échange : se resynchroniser sur un flux dont on a perdu le fil ne produirait qu'un
journal de fiction.

**D5 vaut aussi pour les switchs** : un switch sans rc a son journal quand même, qui dit qu'il n'y
avait rien à envoyer. Un fichier vide est une réponse ; un fichier absent est une question.

**Mesure** (`journal-bench.sh` § J10, **67 assertions, 0 échec** avec `E2E=0` — un switch n'a pas
d'invité, donc ce bout en bout ne démarre **aucune** machine UML). Le rc de mesure tient en trois
commandes, et chacune mesure autre chose : `vlan/create 5` réussit (le journal ne doit pas dire
que tout a raté), `vlan/create 4999` **échoue** — le discriminant, cette erreur n'existait nulle
part avant — et `vlan/print` **rend des données**, ce que l'ancien lecteur ne savait pas lire. Les
lignes de cette dernière prouvent au passage que la première commande a réellement pris effet
**dans** le switch : le journal n'est pas une fiction écrite côté hôte. Le canal sert ce fichier
comme celui d'un invité, `--tail` compris, et continue de le servir après `poweroff` (D3).

*Limite connue, assumée :* le chemin se calcule à partir du **nom**. Un switch renommé entre deux
démarrages laisse donc derrière lui le journal de son ancien nom, et le canal répond, sous le
nouveau, « jamais démarré » jusqu'au prochain lancement. Corriger cela demanderait la machinerie
de renommage que seuls machines et routeurs ont (pour leur hostfs) ; le prix n'en vaut pas la
peine tant que le journal est vivant et refait à chaque démarrage.

### 4.5 Ce que l'épisode 5 a livré (et pourquoi la méthode ne vit pas où on l'attendait)

Le verbe `switch-info` est le **miroir** de `log`, et c'est ce qui décide de tout le reste : `log`
sert ce qu'un composant a **écrit** — un fichier, qui lui survit —, `switch-info` demande ce qu'un
switch **sait**, qui n'est écrit nulle part et n'existe que dans le processus vivant. D'où deux
verbes et non un, d'où la même orthographe (`switch-info <switch> [<table>|--table=<table>]`,
décalquée de `log` et de `rc-get`), et d'où le refus, quand le switch est éteint, qui renvoie
vers `log` : des deux, un seul survit à l'extinction.

**Le protocole a de nouveau été mesuré avant d'être analysé**, sur le même `vde_switch 2.3.2`
qu'à l'épisode 4, et c'est la mesure qui a fixé le nombre de tables :

| Nom (le nôtre) | Commande (celle de vde) | Ce qu'elle répond |
|---|---|---|
| `ports` | `port/print` | qui est branché où, et combien est passé — un port porte ses compteurs et ses *endpoints* |
| `macs` | `hash/print` | quelle MAC apprise sur quel port, et depuis combien de temps |
| `vlans` | `vlan/print` | quel VLAN existe, et quel port lui appartient (taggé ou non) |
| `fstp` | `fstp/print` | l'arbre couvrant — **ou le fait qu'il est désactivé**, que la mesure a montré caché en fin de la ligne d'en-tête (`FST DATA VLAN 0000 ROOTSWITCH FSTP IS DISABLED`) |

`vlan/print` ne figurait pas dans D4 ; il y a été ajouté parce que c'est **la table qui répond à
l'épisode 4** : un rc de switch configure des VLAN, et rien jusqu'ici ne permettait de vérifier
que la configuration avait pris — le banc le mesure maintenant en recoupant les deux épisodes
(le VLAN 5 créé par le rc apparaît dans l'instantané). Sans nom d'aucune sorte, les quatre
tables partent en **un seul aller-retour** : c'est la première question d'un agent (« tout sur
`sw1` »), et la lui faire payer d'une boucle sur une liste qu'il devrait connaître serait la
punir de ne pas connaître la grammaire.

**Chaque table porte les deux moitiés** : `entries`, les lignes analysées en objets JSON, et
`lines`, les mots du switch tels quels. Les premières sont ce qui rend le discriminant écrivable
(`select(.mac == …)` plutôt qu'une expression rationnelle dans une chaîne échappée) ; les
secondes sont ce qui empêche notre analyseur d'être une perte : si vde change une colonne, le
canal continue de servir ce que le switch a dit. Les analyseurs lisent des **mots**, jamais des
regexps — `Str` garde son dernier appariement dans un global, ce sur quoi un lecteur qui tourne
dans le thread d'une connexion n'a rien à parier —, et la moitié des champs sont déjà écrits
`clé=valeur` par vde lui-même. Une table que le switch **refuse** porte son code et ses mots,
et aucune entrée : publier une liste vide là où la vérité est « il a dit non » serait un mensonge.

**Le point de conception de l'épisode ne s'est pas révélé où on l'attendait.** Le plan disait :
une méthode `management_socket_if_any` sur l'ancêtre commun du niveau utilisateur, redéfinie dans
`switch.ml`, jumelle de `rc_journal_file_if_any` (épisode 4). C'est faux, et le compilateur l'a
dit tout de suite : la valeur d'instance `state` — l'automate qui **porte** le device simulé —
n'est pas dans l'interface (`user_level.mli` ne déclare que des méthodes), donc **aucune
sous-classe d'un autre module ne peut la lire**. La méthode ne peut donc pas vivre dans
`component`, où vivent ses deux cousines : elle vit dans `simulated_device`, là où l'état est.

Et une fois là, elle n'a plus besoin d'être redéfinie **nulle part** : `get_management_socket_name`,
ajoutée à la classe `device` du niveau simulation avec `None` pour défaut, répond déjà pour tous
les autres genres — un hub compris, qui fait tourner le **même** `vde_switch` mais que Marionnet
lance sans socket de management. Une définition, aucun cas particulier. Le nom porte la seconde
moitié de la leçon : `management_socket_if_running`, pas `_if_any`, parce que le device existe
aussi quand le composant est **éteint** (il est créé avant d'être lancé) et quand il est
**suspendu** — et un switch suspendu par SIGSTOP ne répondrait pas : il ferait expirer le délai
de lecture. Ce que la méthode refuse de dire, le serveur le dit en mots, puisqu'il lit l'état de
toute façon.

**Quatre refus, quatre nouvelles différentes** — le critère du chantier depuis l'épisode 3 : un
composant inconnu ; une **machine** ou un routeur, à qui l'on rappelle qu'ils répondent en
écrivant (`log`) ; un **hub**, à qui l'on dit qu'il fait tourner le même programme sans la socket
qui permettrait de l'interroger ; un switch **arrêté ou suspendu**, à qui l'on dit que ces tables
sont la mémoire d'un processus, et que ce qu'il a dit à son démarrage, lui, se lit encore. Le
quatrième cas — le switch qui ne répond pas dans le délai — est le seul à ne pas être un
`bad_argument` : c'est un `timeout`, et il nomme la socket.

**6ᵉ application de la règle d'unicité** : `help` publie `switch_tables`, la complétion Bash le
**demande** au lieu d'en tenir copie, et les noms de switchs qu'elle propose viennent de la
session vivante (`ls`, filtré sur le genre) — parce que le verbe ne s'applique qu'à eux. Les deux
refus de forme que `switch-info` partage avec `log` (option mal tapée, choix donné deux fois) ont
été **sortis** des deux clauses d'aiguillage : ils sont maintenant écrits une fois
(`optional_choice_of`), de sorte qu'un troisième verbe de la même forme ne puisse pas en dériver.

Les deux bornes de l'épisode 4 valent telles quelles, et pour la même raison : on lit un processus
qu'on ne contrôle pas (5 s de délai de réception, 4096 lignes par réponse). Rien n'est écrit sur
disque — un instantané, c'est **maintenant** —, et le flux `debug/add` reste en réserve (D4).

**Mesure** : `journal-bench.sh` § J11 — **22 assertions sans démarrer une seule UML** (la
grammaire, les refus, les quatre tables, le recoupement avec l'épisode 4 ; banc entier en `E2E=0` :
**89 assertions, 0 échec**), puis **9 de plus** pour le discriminant en bout en bout (banc entier
en `E2E=0 E2E_SNAP=1` : **98 assertions, 0 échec**) : une machine trixie câblée à `sw1`, démarrée,
dont la MAC lue dans le treeview `ifconfig` apparaît dans la table `macs` de `sw1` **avec son port
et son âge** — et **pas** dans celle de `sw2`, allumé au même moment, sans câble. Le témoin est ce
qui fait la preuve : sans lui, une table pleine ne dirait pas de quel switch elle parle. Complétion :
`completion-bench.sh` § L22, **58 assertions** (53 avant), dont le discriminant historique du § L18
— les verbes proposés sont **exactement** ceux que `help` publie.

Le premier passage du bout en bout a échoué, et **pas** sur le mécanisme : la machine de mesure
avait été créée **sans configuration de démarrage**. Or le marqueur `marionnet-guest-ready`
n'est écrit par personne d'autre que le scénario, et un invité qui n'a rien à faire peut n'émettre
**aucune trame** — donc `wait --ready` expirait, et la table des MAC était légitimement vide
pendant que celle des **ports** montrait déjà l'endpoint du câble. Le scénario de mesure fait
maintenant les deux : un `ping` vers un voisin **inexistant** (la requête ARP part en diffusion
avec notre MAC en source, sans qu'aucun pair n'ait à répondre), puis le marqueur.

### 4.6 Ce que l'épisode 6 a livré (et pourquoi il n'ajoute presque aucun argument)

La console est la sonde de la décision **D2** : la seule qui voie un démarrage **qui n'atteint
jamais le relais**, et la seule que l'invité ne puisse pas récrire — les deux journaux des
épisodes 1-2 vivent dans un hostfs que l'étudiant peut réécrire, celui-ci est un fichier de
l'hôte, `<répertoire de travail du projet>/<nom>-console.log`, à côté du journal d'un switch
(épisode 4). Enregistrement **sur option** (`--console-log`), **implicite en `--exam`**, et
aucun attribut persisté : c'est une propriété de la **session**, pas du projet (D5).

**La mesure a réduit le mécanisme à presque rien.** Les trois pistes du plan (`fd:` sur un
descripteur, `tty:` sur un pty, l'xterm sous `script(1)`) supposaient toutes qu'il fallait
*ajouter* une console. Or un UML en a déjà une :

- **sans aucun argument `console=`, le noyau écrit sur la console `stderr0`**, c'est-à-dire sur
  la **sortie d'erreur du processus UML** — jusqu'ici `/dev/null`. Rediriger la sortie standard
  et la sortie d'erreur du processus suffit donc, et **aucun argument noyau n'est ajouté** ;
- **le premier `console=` explicite l'éteint** (`printk: legacy console [stderr0] disabled`).
  Marionnet en pose un pour le couple 6.12/systemd (`console=tty0`, *boot quirk*) : là, et là
  seulement, il faut rendre une ligne à la place — `ssl0=null,fd:1` (la ligne série sort sur la
  sortie standard héritée ; entrée `null`, le fichier étant ouvert en écriture seule) et
  `console=ttyS0` placé **en tête**, de sorte que le **dernier** `console=` reste celui qui
  était là : `/dev/console`, donc l'xterm de l'étudiant et son *getty*, ne bougent pas.

**Le piège de l'épisode est systemd, et il coûte 90 secondes.** Une console série active apparaît
dans `/sys/class/tty/console/active`, où `systemd-getty-generator` la lit pour instancier
`serial-getty@ttyS0.service` — lequel `BindsTo` un `dev-ttyS0.device` que UML ne crée jamais.
Mesuré : le boot attend `Job dev-ttyS0.device/start running (…/1min 30s)`, puis échoue — ce qui
en prime aurait pollué le `systemctl --failed` du collecteur de l'épisode 2. D'où
`systemd.mask=serial-getty@ttyS0.service`, ajouté **seulement** quand l'invité est déclaré
systemd. Sous SysV il n'y a rien à faire : l'`inittab` de Debian a sa ligne `ttyS0` en commentaire
(vérifié dans l'image wheezy sans la monter, par `debugfs`).

Le descripteur est ouvert à la construction du `uml_process` et **fermé dans le parent juste
après `spawn`** : l'enfant en a reçu sa copie au `fork`, et une session longue ne fuit pas un
descripteur par machine démarrée. La sortie standard **de UML lui-même** est enregistrée aussi,
délibérément : un UML qui refuse de démarrer se plaint là, et cela partait dans `/dev/null`.

**Côté canal, le troisième journal n'a pas coûté un troisième cas.** La source à trois cas de
l'épisode 4 (`Js_hostfs` / `Js_file` / `Js_none`) est devenue une **liste** `(nom, chemin,
pourquoi-il-manque)` : ce qu'un composant sert est désormais une propriété du composant, et
chaque entrée porte **la phrase à dire quand le fichier n'est pas là** — parce que cette phrase
est ce qui apprend à un script s'il doit *attendre*, *démarrer* quelque chose, ou *relancer
Marionnet autrement*. Elle n'est jamais la même :

| Demande | Ce que le refus dit |
|---|---|
| `log m1` (rc_config), invité pas encore prêt | « … or its guest has not reached the end of its boot — see `wait --ready` » |
| `log m1 console`, session sans enregistrement | « this session does not record consoles: restart Marionnet with `--console-log` (implied by `--exam`) » |
| `log m1 console`, session enregistrante, machine jamais démarrée | « it has not been started since this project was opened » — et **pas** de renvoi vers `wait --ready` : ce journal-là ne dépend pas de l'invité |
| `log sw1 console` | « a switch runs no guest system of its own: it boots nothing and has no console … (it serves rc_config) » |

Aucune méthode nouvelle n'a été ajoutée aux classes : le chemin de la console est une fonction du
projet et du nom, tous deux déjà connus du serveur — contrairement à l'épisode 5, où l'état du
composant était indispensable. Et la complétion Bash n'a pas été touchée : `help` publie `logs`,
qui en compte maintenant trois. Septième application de la règle d'unicité, et la première qui ne
coûte rien.

**Le discriminant a dû être changé, et ce qui l'a empêché est une bonne nouvelle.** Le plan
voulait « une image dont l'`init` est cassé ». Fabriquer un tel couple **par le canal** n'est plus
possible : le remap automatique de `marionnet-retro-compat-kernels-images` corrige un vieux noyau
inutilisable (`3.2.64-ghost` → `6.12.95-i386`, mesuré), et un noyau hors des `SUPPORTED_KERNELS`
de l'image est refusé net. Le banc coupe donc **le courant en plein boot** (`poweroff` 8 s après
`start`) : le relais n'a pas eu le temps d'exister, le hostfs ne porte **aucun** journal, et la
console, elle, porte tout le démarrage — la propriété que l'épisode voulait montrer, obtenue à
coup sûr.

### 4.7 Ce que l'épisode 7 a livré (et les deux fois où le mécanisme était mort)

Le § 2.4 disait que le mode examen faisait « déjà la moitié du travail ». La mesure a corrigé :
il n'en faisait **rien du tout**, et pour deux raisons superposées, dont la seconde n'a été vue
qu'en instrumentant.

1. **Personne n'écrivait** `report.html` ni `bash_history.text` (§ 2.4).
2. **Et personne ne pouvait les lire** : `import_file` **lève** sur un fichier absent, en
   affichant un dialogue d'erreur. Éteindre une machine en mode examen produisait donc une
   exception, à chaque fois, depuis des années. D'où le garde par existence dans le geste
   d'import, qui n'est pas une précaution mais la condition pour qu'un journal qu'un invité
   donné ne produit pas ne coûte rien à l'extinction.

**L'historique n'est pas capturé à l'arrêt : il est écrit en continu.** Le producteur historique
(`uml/startup.old/marionnet_grab_config`) copiait `/root/.bash_history` depuis un script d'arrêt ;
c'était fragile deux fois — un Bash interactif tué pendant un shutdown n'écrit rien, et l'outil
qu'il appelait (`cfg2html`) n'existe plus dans les images modernes. À la place, le **prologue**
dépose dans l'invité un `/etc/profile.d/marionnet-journal.sh` (accroché aussi en fin de
`/root/.bashrc`, pour les shells non-login) qui met le `HISTFILE` **dans le hostfs** et ajoute
`history -a` au `PROMPT_COMMAND` : le fichier est à jour à chaque invite. Il se lit donc **à
chaud**, il est là au moment de l'archivage, et il ne dépend d'aucune séquence d'arrêt.

**Il est horodaté, et c'est ce qui le rend utile à un correcteur.** `HISTTIMEFORMAT` fait écrire
à Bash une ligne `#<epoch>` avant chaque commande : les séances de `m1`, `m2`, `r1` **se
fusionnent** en une chronologie unique, lisible par un agent sans rien deviner. Le `PS1`, lui,
n'est **pas** touché : une horloge dans l'invite ferait croire à l'étudiant que sa vitesse est
mesurée (elle ne l'est pas), et elle n'atteindrait de toute façon aucun fichier — le journal de
console de l'épisode 6 enregistre la sortie du *processus* UML, tandis que la session de
l'étudiant vit sur un device UML séparé (`con0`), capturé nulle part.

Côté canal, c'est un **quatrième** journal, nommé `commands` — et **pas** `history`, qui est déjà
un **verbe** de la grammaire (le treeview des états sauvegardés). Un mot, un sens : même leçon
qu'à l'épisode 3 avec `--file`, déjà pris côté client. Son refus ne dit pas la même chose que
celui des trois autres : il ne renvoie pas vers `wait --ready`, parce qu'une machine parfaitement
prête peut n'avoir aucune commande tapée.

**Le rapport est en Markdown, et c'est une décision de producteur, pas de goût.** Le producteur
est du Bash dans un invité minimal : en HTML il faudrait échapper `&`, `<`, `>` sur **chaque**
sortie de commande, et un seul `<` oublié casse la page en silence ; en Markdown la sortie entre
telle quelle dans un bloc clôturé — clôturé à **quatre** backticks, pour qu'une sortie qui en
contient trois reste dans son bloc. Un agent le lit sans traverser de balises, et en GUI il tombe
sur l'éditeur de texte plutôt que sur le défaut historique du format HTML (`galeon`, mort depuis
2010). Le prix est une ligne dans `file_to_format` : `.md` (et `.log`, pour la console) sont
rendus au format **`text`** existant — aucun format nouveau ne descend dans un `.mar`. Le lire
*rendu* depuis la GUI est l'épisode 9.

**L'unité systemd est toute la difficulté du hook d'arrêt, et il a fallu deux mesures.**

- `Conflicts=shutdown.target` est ce qui fait **arrêter** l'unité — donc jouer son `ExecStop` —
  pendant l'extinction. Écrite avec `DefaultDependencies=no` et sans ce `Conflicts`, l'unité
  n'est jamais arrêtée : elle est tuée à la fin, et rien n'est écrit. Mesuré : témoin absent.
- Mais la forme implicite (dépendances par défaut, qui portent ce `Conflicts`) ne suffit pas non
  plus : l'`ExecStop` n'est alors ordonné contre rien, le reste de l'arrêt court en parallèle, et
  l'invité **s'éteint au milieu du rapport**. Mesuré : un rapport coupé net en pleine commande.
  D'où la forme explicite — `DefaultDependencies=no` + `Conflicts=shutdown.target` +
  `Before=shutdown.target umount.target` + `After=network.target` — qui met notre `ExecStop`
  **en premier** et fait attendre tout le reste. Rapport complet, 19 sections.

**Limite mesurée, et elle ne vient pas de nous : les vieilles images SysV n'ont pas de séquence
d'arrêt.** Marionnet éteint un invité par `uml_mconsole cad`, et l'`inittab` de ces images répond
`ca:12345:ctrlaltdel:/sbin/halt` — un contournement Marionnet délibéré (un `-r` faisait planter
les noyaux 3.2.x, cf. le wrapper `/sbin/shutdown` de ces images) qui **court-circuite
`/etc/rc0.d`**. Le lien `K01` que l'épilogue y pose est donc correct mais ne se déclenche que
lorsque l'arrêt est demandé **depuis** l'invité. Ces images gardent leur historique et leurs deux
journaux de boot, qui ne dépendent d'aucun arrêt.

**Et le routeur ?** La symétrie du § 2.4 est tranchée : machine et routeur appellent désormais le
**même** geste (`import_exam_documents`), donc le routeur gagne l'historique et la console qui lui
manquaient. Mais elle n'est mesurable qu'à moitié : la seule image de routeur installée
(`router-guignol-18474`, un lien vers une image de 2014, i386/SysV) **n'atteint pas son relais**
sur cet hôte — hostfs sans aucun journal après 240 s. Le banc le dit et poursuit ; le jour où une
image de routeur moderne existera, ses assertions se joueront sans être touchées. Ce qui marche
déjà pour lui : sa **console** est archivée (elle ne dépend pas de l'invité), et on la voit dans
le treeview.

**Le piège de l'épisode est ailleurs que dans le code : `stop` rend la main avant la fin.** La
tâche « Stopping m1 » vit dans la file de Marionnet, et l'archivage est la **dernière** chose que
fait l'extinction. Un script (ou un banc) qui lit `documents` juste après `stop` lit un treeview
encore vide — et s'il enchaîne sur `close`, il ferme le projet sous les pieds de l'archivage, qui
ne trouve alors même plus le répertoire. D'où le `wait <c> --state=off` avant de lire, qui est de
toute façon ce qu'un script doit faire.

### 4.8 Ce que l'épisode 8 a livré (et le crochet que le noyau n'offre pas)

L'épisode 7 laisse un correcteur avec les **commandes** (`commands`) et les **messages du noyau**
(`console`), mais pas avec **ce que l'étudiant a vu** : une commande sans sa sortie ne dit pas si
elle a marché. Ce qui manquait est le contenu de la **fenêtre** — et cette fenêtre, ce n'est pas
Marionnet qui l'ouvre : c'est le noyau UML, à qui l'on passe `xterm=<émulateur>,-T,-e`
(`simulation_level.ml`, valeur `MARIONNET_TERMINAL`).

**Trois mesures ont décidé de la forme, dont deux ont tué la piste qui paraissait la bonne.**

1. **`UML_PORT_HELPER` n'est pas lu par le canal `xterm`.** La variable existe bien dans le noyau
   6.12.95 (elle y figure avec son message d'erreur, `strings`), mais elle appartient à
   `port_connection` — le canal `port:`. Mesuré deux fois, dont une avec la variable **présente
   dans l'environnement du processus UML** : le noyau a lancé `/usr/lib//uml/port-helper`, en dur.
   La piste « vendorer un port-helper modifié » tombe donc, faute de crochet.
2. **Le port-helper ne voit passer aucun octet.** Ses seuls appels libc sont
   `socket/connect/bind/sendmsg/ioctl/pause` : il passe le **descripteur** de son terminal au
   noyau (SCM_RIGHTS) et dort. Il n'y a rien à intercepter *dedans* — l'enregistrer supposerait de
   lui faire jouer un rôle qu'il n'a pas (un pty intermédiaire, c'est-à-dire un `script(1)`
   réécrit). Le vendoring aurait donc coûté ~150-200 lignes de C **sans** supprimer la dépendance
   `uml-utilities`, qui reste de toute façon requise par `uml_mconsole` (extinction gracieuse,
   `bin/serial.ml`).
3. **Substituer l'émulateur marche, et l'argv est trivial.** Le noyau lance
   `<émulateur> -T "Virtual Console #0 (m1)" -e /usr/lib//uml/port-helper -uml-socket /tmp/xterm-pipeXXX`.
   Un enregistreur mis à la place du premier champ isole ce qui suit l'*exec switch* et le relance
   sous `script(1)` — qui, lui, met le pty qu'il faut. `script` vient de `bsdutils`
   (**`Essential: yes`**) : aucune dépendance à déclarer.

**Le mécanisme.** `bin/scripts/marionnet-terminal-record.sh` est embarqué (`INCLUDE_AS_STRING`,
donc déclaré dans les `preprocessor_deps`) et déposé **exécutable** dans le répertoire de travail
du projet. Marionnet ne remplace que le **premier** champ de `xterm=` — les deux switches restent
ceux de la configuration de l'utilisateur, que l'enregistreur réutilise pour relancer le vrai
émulateur. Les trois valeurs dont il a besoin (l'émulateur, l'exec switch, le chemin du journal)
arrivent par **l'environnement du processus UML**, ce qui a demandé un `?environment` sur la
classe `process` (`Unix.create_process_env`) : un `putenv` global aurait couru entre deux
démarrages, puisque le chemin dépend du composant. Repli à chaque étape — variable manquante,
`script` absent, argv inattendu, journal impossible à créer : on `exec` l'émulateur intact. **Une
fenêtre doit toujours s'ouvrir** ; l'enregistrement est un supplément, jamais une condition.

**Le journal s'appelle `terminal`, et il n'est pas fusionné dans `console`.** Deux flux, deux
écrivains, deux fichiers : la console est ce que le noyau écrit sur la sortie d'erreur du
processus (ttyS0 en mode enregistré, épisode 6), le terminal est ce qui traverse `con0`. Les
mélanger dans un fichier écrit par deux processus produirait des lignes entrelacées, et perdrait
la distinction qui fait tout l'intérêt. C'est aussi le **discriminant** de l'épisode : un témoin
écrit par le scénario sur `/dev/tty0` apparaît dans `terminal` et **jamais** dans `console`.

**Ce qui est archivé n'est pas ce qui est servi.** Un typescript porte les échappements d'un vrai
terminal (131 lignes en portent, sur un simple boot) : rejoué par `scriptreplay(1)` c'est la
séance, ouvert dans un éditeur c'est illisible. Donc le brut **et** son fichier de timing restent
dans le répertoire du projet, servis par `log … terminal`, tandis que le mode examen archive une
copie **nettoyée** (`Terminal_recording.strip`, un automate sans dépendance). Ce filtre
**n'applique pas** les effacements : une ligne que l'étudiant a retapée apparaît deux fois plutôt
qu'une. Reconstituer l'écran final demanderait d'émuler un terminal, et **supprimerait**
silencieusement ce qu'un correcteur veut peut-être voir.

**Défaut trouvé en mesurant, antérieur à l'épisode** : `Treeview_documents#import_document`
acceptait un `~move` et ne le transmettait **jamais** à `import_file`. Tous les imports étaient
donc des copies, y compris les deux de l'épisode 7 qui demandent un déplacement. Corrigé — et les
intentions revues du même coup, car honorer le drapeau change ce que font les appelants : rapport
et historique sont désormais **explicitement** copiés (le hostfs est recréé au boot suivant, et
déplacer `bash_history.text` ferait taire `log … commands` après une extinction), seule la copie
nettoyée du terminal est déplacée, puisqu'elle n'existe que pour l'archive.

**Limites, toutes mesurées.** Le noyau `linux-3.2.64-ghost` des vieux couples ne connaît pas la
substitution telle qu'on l'emploie ici — l'enregistrement n'y est simplement pas disponible, et le
canal le dit. Ne sont pas vus non plus : un **X NEST** (la console UML est alors `none`), un `ssh`
ouvert depuis une autre machine, un terminal lancé dans un invité graphique. Les couvrir
demanderait `script(1)` **dans** l'invité — falsifiable par l'étudiant, donc un autre arbitrage
que D2. Les **routeurs** démarrent avec `~console:"none"` : rien à enregistrer tant que ce choix
tient, le code étant symétrique.

### 4.9 Ce que l'épisode 9 a livré (et pourquoi la doc a le droit de nommer les journaux)

Huit épisodes ont produit de la matière et un canal pour la lire ; **aucun n'avait touché la
documentation utilisateur**. Le guide `doc-src/scripting/README.md` s'arrêtait aux *tables* (§ 10,
« read what happened » — qui ne lisait justement que ce que Marionnet sait de lui-même), et le mode
examen, réanimé à l'épisode 7 après des années de panne silencieuse, n'avait **pas une ligne** pour
l'enseignant qui ne pilote pas Marionnet par script.

**Le point de conception de l'épisode est une tension, et elle méritait d'être tranchée
explicitement.** L'invariant transverse des deux chantiers dit que la grammaire n'a qu'**une**
source de vérité — le serveur, publiée par `help` — et le guide s'en réclame dans sa dernière
section (« it does not restate the command list… when in doubt, `help` wins over this page »). Or
un § sur les journaux qui n'en **nommerait aucun** n'apprendrait rien : la valeur de la page n'est
pas la liste (que `help` donne), c'est **qui écrit quoi** — trois journaux viennent de l'invité et
sont donc falsifiables par l'étudiant, deux sont écrits par l'hôte et ne le sont pas. Cette
information n'est nulle part dans `help`, et c'est elle qui décide d'une notation.

Arbitrage retenu : **la doc nomme, et le banc compare**. Le § 11 porte un tableau des cinq
journaux, et `doc-bench.sh` extrait ces noms du Markdown pour les confronter à `.logs` de `help` —
la coïncidence devient une **propriété mesurée à chaque passage**, plus une promesse d'auteur.
C'est la 9ᵉ application de la règle d'unicité, sous une forme nouvelle : les huit précédentes
*demandaient* la liste au serveur (client, vérificateur, traducteur, complétion) ; celle-ci la
**cite et la fait vérifier**, parce qu'un lecteur humain n'exécute pas `help` avant de lire une
phrase.

**Livré.** (a) Guide, § 11 neuf (« Recipe E — the journals ») : la forme de `log`, les cinq
journaux et leurs deux natures, le `grep '^!! FAILED'` qui vaut pour une machine, un routeur **et**
un switch, les **trois** refus qui ne disent pas la même chose (attendre l'invité / démarrer le
composant / relancer Marionnet avec l'option), les deux plafonds de nature différente, `switch-info`
en miroir, et les options d'enregistrement — sections suivantes renumérotées (11→15), une seule
ancre interne à corriger. (b) **`doc-src/exam-mode.md`**, note utilisateur en anglais destinée à
l'enseignant : ce que la session enregistre, ce que l'extinction **gracieuse** archive dans le
`.mar`, ce qui est falsifiable et ce qui ne l'est pas, et les limites **mesurées** (images SysV
sans séquence d'arrêt, image de routeur de 2014 qui ne boote pas, rapport Markdown lu aujourd'hui
comme du texte brut — c'est l'épisode 10). (c) Deux exemples exécutables, `04-journals.sh` et
`05-exam-session.sh`, joués **tels quels** par les bancs, comme les trois précédents.

**Ce que l'écriture des exemples a mis au jour.** `wait <c> --state=off` **ne suffit pas** à
garantir que l'archivage du mode examen est fini : la transition d'état précède l'import
(`gracefully_shutdown_right_now` archive **puis** détruit, mais l'état est déjà passé), si bien
qu'un script qui lit `documents` juste après peut lire un treeview encore vide. Le piège de
l'épisode 7 était donc **plus fin** que ce qu'on en avait écrit : l'attente de l'état est
nécessaire, pas suffisante. L'exemple 05 attend donc, en plus et de façon **bornée**, que le
treeview se remplisse — jamais un `sleep` fixe, jamais une attente infinie — et le dit dans son
commentaire. Corollaire côté banc : puisque l'exemple **fait** l'extinction gracieuse de la
machine, la section E4b d'`exam-bench.sh` ne l'éteint plus qu'à la condition qu'elle tourne
encore.

Et un mot qui n'est pas un détail : un exemple joué par un banc **ne peut pas mentir longtemps**.
C'est la seule forme de documentation que ce chantier considère comme livrée.

## 5. Rapports avec les autres chantiers

- **`pilotage-par-script`** — fournit le canal (`control_server.ml`, `mrnctl`) qui **lit** le
  journal (ép. 3, 5). D1 fait que ce chantier-ci n'en dépend pas pour produire la matière.
- **`kernel-rootfs-refresh`** — premier client : les ép. 2 et 6 lui donnent de quoi valider une
  image sans intervention humaine. Aucune dépendance dans l'autre sens (D1).
- **`bug-critique-crash-host`** — la capture de console (ép. 6) fournirait une pièce à la
  checklist post-mortem, aujourd'hui aveugle sur le côté invité.
- **`migration-marshal-to-text`** (clos) — D5 protège son acquis : aucun attribut persisté ajouté,
  le format v3 n'est pas rouvert.

## 6. Reste au chantier

- Le **flux d'événements** du switch (`debug/add`) : mis en réserve par D4, à ouvrir seulement si
  une question temporelle le réclame.
- L'erreur de glob des images sans `<image>.relay` (§ 2.1) : hors de portée sans rebuild ; à
  signaler à `kernel-rootfs-refresh` s'il reconstruit le relais.
- Les **hubs** n'ont pas de socket de management (`~management_socket:()` n'apparaît que dans
  `switch.ml`) : leur observabilité n'est pas au programme et coûterait de l'ajouter.
- Un **rapport plus riche** que celui de l'épisode 7 (successeur libre de `cfg2html`, à chercher
  et évaluer parmi les outils empaquetables) : sujet à part entière, éventuellement précédé d'une
  recherche. Ce que l'épisode livre est un rapport **sobre et sûr**, et l'endroit où un rapport
  plus riche viendra se brancher.
- Le **rapport de fin de session sur les images SysV** : impossible tant que leur `inittab`
  répond au ctrl-alt-del par `/sbin/halt` (§ 4.7). Le remède serait d'envelopper `/sbin/halt`
  dans le COW — le motif que ces images utilisent déjà pour `/sbin/shutdown` — mais toucher au
  binaire d'arrêt d'un invité pour un journal n'a pas paru un bon marché ; à rouvrir seulement si
  un TP doit être noté sur une vieille image.
- Le **bout en bout du routeur** attend une image de routeur qui boote (§ 4.7) ; le code, lui,
  est symétrique depuis l'épisode 7.
- **Constaté à l'épisode 7, hors périmètre** : sur une `debian-wheezy`, `rc_config.log` ne porte
  que son en-tête — la capture du prologue (épisode 1) n'y attrape rien, alors que le `set -x`
  fonctionne (mesuré : la trace part bien dans un fichier que le scénario redirige lui-même). Le
  collecteur (`boot.log`), lui, est complet sur la même image. À instruire.

## Journal d'avancement

### 2026-08-10 — Épisode 0 : officialisation

Chantier ouvert. Étude menée depuis l'objectif « monitorer machines, routeurs et switchs comme le
fait `-d` ». Quatre sondes exécutées avant toute décision (§ 2) : ordre réel du glob de sourcing du
relais, sémantique exacte de `Debug_level`, capacités réelles de la socket de management d'un
`vde_switch 2.3.2`, et recherche du producteur des fichiers du mode examen.

Deux d'entre elles ont changé le plan. La première a montré qu'**il n'y a rien à ajouter au relais
invité** : le glob existant offre déjà un prologue et un épilogue à qui écrit dans le hostfs, donc
le chantier se libère de toute dépendance envers `kernel-rootfs-refresh` (D1). La quatrième a montré
que le mode examen **importe depuis toujours des fichiers que personne ne produit** — le
consommateur (`treeview_documents`) est vivant et persisté dans le `.mar`, le producteur a disparu
des images. Le chantier ne conçoit donc pas une destination : il en réanime une (D3, ép. 7).

L'objectif s'est élargi en séance : capturer la console, ce n'est pas seulement voir une panique
noyau, c'est enregistrer **le travail d'un étudiant**, donc ouvrir la voie à un mode examen dont la
correction pourrait être assistée. Le critère qui départage les deux supports est apparu là : le
hostfs est inscriptible par l'invité, la capture côté hôte ne l'est pas (D2).

Décisions D1 à D7 arrêtées, structure en 8 épisodes + 2 optionnels (§ 4). Aucun fichier de `bin/`,
`lib/` ou `uml/` touché.

### 2026-08-10 — Épisode 1 : le prologue injecté

`bin/scripts/marionnet-relay.00-journal.sh` et `bin/scripts/marionnet-relay.zz-journal.sh`, déposés
**inconditionnellement** dans le hostfs par `make_hostfs_content` (`bin/simulation_level.ml`) —
donc pour les machines **et** les routeurs, `uml_process` étant commune aux deux. Le contenu est
embarqué à la préprocession par `INCLUDE_AS_STRING`, l'idiome déjà employé par `bin/gui/talking.ml`
(motif immédiat : `camlp4of` ne parse pas les chaînes `{|…|}`, vérifié ; motif de fond : aucune
étape d'installation entre le binaire et ce qu'il dépose).

**Mesure** (`journal-bench.sh`, hors dépôt, **26 assertions, 0 échec**) : une trixie ajoutée,
configurée et démarrée **par le canal**, avec un `rc_config` de trois lignes dont la seconde échoue.
Le journal côté hôte porte les cinq matières attendues — la sortie standard, la sortie d'erreur, la
trace des commandes (`PS4` datée du fichier et de la ligne), le **statut** de la commande fautive,
et la preuve que le scénario a **continué** :

```
++ marionnet-relay.rcfile:2: ls /journal-bench-no-such-path
ls: cannot access '/journal-bench-no-such-path': No such file or directory
!! FAILED (status 2): ls /journal-bench-no-such-path
++ marionnet-relay.rcfile:3: echo 'journal-bench: apres la panne'
```

Trois assertions comptent plus que les autres. Le **témoin** : le journal est le **seul** fichier du
hostfs qui garde une trace de l'échec — c'est la mesure de ce qui n'existait pas. La **non-fuite** :
la dernière ligne du fichier est celle de l'épilogue, donc rien de la fin du boot n'a été aspiré
(si la redirection avait survécu, tout ce que le relais affiche ensuite se serait ajouté après
elle). Et **D5** : une seconde machine, sans aucun `rc_config`, a elle aussi son journal, ouvert et
clos — un script trouve le journal sans connaître de drapeau.

Le premier run a mis en défaut deux choses, et aucune n'était le mécanisme : une assertion du banc
(le premier caractère de `PS4` est répété **par niveau d'imbrication**, et le `rcfile` est sourcé
depuis une fonction — donc `++`, jamais `+`), et surtout la **dépendance invisible** de dune envers
les scripts embarqués (§ 4.1), qui faisait tourner le banc contre un binaire périmé. C'est le banc
qui a réclamé la comparaison octet à octet du fichier déposé avec sa source ; c'est cette
comparaison qui garde la synchronisation vérifiée à chaque run.

### 2026-08-10 — Épisode 2 : le collecteur

Greffé à la fin de `marionnet-relay.zz-journal.sh`, comme prévu, sans toucher au prologue ; il
écrit un **second** fichier, `/mnt/hostfs/boot.log`, parce que « qu'a fait mon scénario ? » et
« cette image a-t-elle démarré ? » sont deux questions (§ 4.2). Côté OCaml, **une ligne** : la
liaison `init_system` dans `boot_parameters`, pour que la collecte puisse confronter ce que l'hôte
**déclare** à ce qu'elle **détecte** — ce même `init_system` sélectionnant les `boot_quirks` du
noyau, un désaccord vaut d'être vu.

Le chantier voulait « selon `init_system` (déjà connu de Marionnet) » ; l'implémentation a inversé
la source : c'est l'**invité** qui décide de la branche, par le test de systemd lui-même
(`/run/systemd/system`), la déclaration de l'hôte n'étant plus qu'un **témoin** journalisé. Un
fichier qui prétend dire ce que le boot a fait ne peut pas croire l'hôte sur parole.

**60 assertions, 0 échec**, trois invités démarrés par le canal. Le discriminant est tenu des deux
côtés : sur trixie, une unit `oneshot` installée par le scénario apparaît côté hôte dans
`systemctl --failed`, sans aucun xterm ; sur `debian-wheezy-08367` — une image de **2013**, sysv,
i686 — la même collecte s'écrit sans erreur et sans interroger systemd. **D1 est ainsi mesuré, pas
seulement raisonné** : une image antérieure de treize ans au chantier produit son journal parce que
l'hôte l'a injecté dans le hostfs, sans que rien ne soit reconstruit.

Quatre choses ont été apprises en mesurant plutôt qu'en lisant : une image Marionnet peut n'avoir
**aucun syslog** (d'où le listing de `/var/log`, inconditionnel) ; le tampon d'un noyau UML n'a pas
toujours sa bannière ; sous systemd, `journalctl -b` **rapporte nos propres lignes**, ce qui a
élargi le témoin de l'épisode 1 et montré au passage que le prologue enrichit aussi le journal
système de l'invité ; et l'ordre du glob de sourcing est **inversé** dans le relais de wheezy, sans
conséquence pour nos trois fichiers. Détail des quatre : § 4.2.

### 2026-08-11 — Épisode 3 : le canal lit

Verbe `log` dans `bin/control_server.ml` : le canal sert désormais les **deux** fichiers que les
épisodes 1 et 2 ont fait écrire, sans qu'un script ait à connaître le chemin d'un hostfs. La forme
est celle de `rc-get`, le défaut est le journal du scénario, et les deux plafonds — 400 lignes pour
la réponse, 2 Mio pour le lecteur — n'ont pas la même raison d'être (§ 4.3). Rien de neuf n'a été
inventé côté résolution : la recherche du hostfs de `wait --ready` a été **extraite** (`find_hostfs`)
et partagée par les deux verbes, avec sa discipline — le créneau GTK pour trouver le composant, le
thread appelant pour l'I/O.

L'épisode n'a mis en défaut ni le mécanisme ni une attente : le premier run a échoué sur trois
assertions **du banc**, qui vérifiaient le texte d'un refus avec `expect_ok` — lequel exige
`.ok == true`, donc ne peut rien dire d'un refus. D'où `expect_detail`, qui ne regarde que
`.detail` ; les refus, eux, disaient déjà ce qu'il fallait.

Le seul piège réel était côté client : `--file` appartenait déjà à `mrnctl` (le mode batch), où il
désigne un chemin. La cohabitation est sans danger dans la ligne de commande (les options du client
s'arrêtent au verbe), mais la complétion proposait des fichiers de l'hôte là où le canal attend un
journal ; elle a appris la distinction — et, comme aux épisodes 10 et 12 du chantier frère, elle
**demande** les deux noms au serveur (`help` publie `logs`) plutôt que d'en tenir une copie.

**84 assertions, 0 échec** au banc du chantier (dont le discriminant sur une machine encore
allumée), **53** au banc de complétion. `doc-src/scripting/` n'a pas été touché : la documentation
utilisateur du chantier est l'épisode 8.

### 2026-08-11 — Épisode 4 : le switch cesse de jeter les réponses de son rc

Le nom disait le défaut : `send_commands_to_vde_switch_ignoring_answers` lançait un thread dont
l'unique travail était de lire les réponses **pour les jeter**, et cadençait l'envoi par un délai
de 1/100 s. Une configuration VLAN fautive échouait donc en silence total — ni fichier, ni GUI,
ni canal. Depuis cet épisode, Marionnet écrit ce qu'il a dit à `vde_switch` et ce que `vde_switch`
a répondu, dans `<répertoire de travail du projet>/<nom>-rc_config.log`, servi par le verbe `log`
de l'épisode 3. Le délai a disparu avec le rejet : **lire la réponse *est* le cadencement**.

Le protocole a été **mesuré avant** d'être analysé (interrogatoire d'un `vde_switch 2.3.2` réel),
et la mesure a condamné le lecteur booléen que le fichier gardait « useful for testing » : il ne
connaît que `vde$ 1000 Success`, or la ligne de statut d'une réponse **qui porte des données**
n'est pas préfixée par l'invite — il passait devant le terminateur de toute commande qui affiche
quelque chose. Supprimé, remplacé par un lecteur qui sait les deux formes (§ 4.4).

Le point de conception était **où mettre le journal** : un switch n'a pas d'invité, donc pas de
hostfs. Il est écrit par l'hôte, dans le répertoire de travail du projet — journal *vivant* au
sens de D3 —, et le verbe `log` n'a pas eu besoin d'un frère mais d'une **source** à trois cas
(un répertoire, un fichier, rien), d'où trois refus qui ne disent pas la même chose. Côté modèle,
une méthode jumelle de `hostfs_directory_if_any` sur l'ancêtre commun, exclusive d'elle par
construction.

**67 assertions, 0 échec** (`journal-bench.sh` § J10), et ce bout en bout ne démarre **aucune**
machine UML : un switch n'a pas d'invité, donc le discriminant du chantier se mesure ici en
quelques secondes. Trois commandes suffisent à le tenir — une qui réussit, une commande VLAN
fautive, une qui rend des données —, et les lignes de la troisième prouvent que la première a
réellement pris effet **dans** le switch. La ligne d'échec reprend la forme des épisodes 1 et 2
(`^!! FAILED`) : un seul `grep` répond désormais pour une machine, un routeur et un switch.

### 2026-08-11 — Épisode 5 : l'instantané du switch

Le verbe `switch-info` est le **miroir** de `log` : celui-ci sert ce qu'un composant a **écrit**,
celui-là demande ce qu'un switch **sait** — quatre tables (`ports`, `macs`, `vlans`, `fstp`) qui
n'existent que dans le processus vivant et que rien n'écrit nulle part. D'où le refus, quand le
switch est éteint, qui renvoie vers `log` : des deux, un seul survit à l'extinction. Le protocole
a de nouveau été **mesuré avant** d'être analysé, et la mesure a ajouté une quatrième table à
celles que D4 prévoyait : `vlan/print` est la table qui **répond à l'épisode 4** — un rc de switch
configure des VLAN, et rien ne permettait jusqu'ici de vérifier que la configuration avait pris.

Chaque table porte les **deux moitiés** : `entries` analysées en objets JSON (ce qui rend le
discriminant écrivable) et `lines`, les mots du switch tels quels (ce qui empêche notre analyseur
d'être une perte). Les analyseurs lisent des **mots**, pas des expressions rationnelles : `Str`
garde son dernier appariement dans un global, ce sur quoi un lecteur qui tourne dans le thread
d'une connexion n'a rien à parier.

Le point de conception ne s'est **pas** révélé où on l'attendait. Le plan calquait l'épisode 4 —
une méthode sur l'ancêtre du niveau utilisateur, redéfinie dans `switch.ml` — et c'était faux : la
valeur d'instance `state`, qui porte le device simulé, n'est pas dans `user_level.mli`, donc
**aucune sous-classe d'un autre module ne peut la lire**. La méthode vit donc dans
`simulated_device`, là où l'état est ; et une fois là, elle n'est redéfinie **nulle part**, parce
que `get_management_socket_name` (ajoutée à la classe `device` avec `None` pour défaut) répond
déjà pour tous les autres genres — un **hub** compris, qui fait tourner le même `vde_switch` sans
socket de management. Le nom dit le reste : `management_socket_if_running`, parce que le device
existe aussi **éteint** (créé avant d'être lancé) et **suspendu** (SIGSTOP : il ferait expirer le
délai de lecture). Ce que la méthode refuse de dire, le serveur le dit en mots (§ 4.5).

**22 assertions sans UML** (`journal-bench.sh` § J11 ; banc entier `E2E=0` : 89, 0 échec) et **9
de plus** pour le discriminant, qui demande une vraie machine (banc entier `E2E=0 E2E_SNAP=1` :
98, 0 échec) : la MAC de `m5` est apprise par `sw1`, avec son **port** et son **âge**, et `sw2` —
allumé au même moment, sans câble — ne la connaît pas. Le seul échec du premier passage était
dans le **banc** : une machine sans rc n'écrit pas le marqueur de `wait --ready` et peut n'émettre
aucune trame ; le scénario de mesure émet maintenant une requête ARP vers un voisin inexistant,
puis signale. La complétion Bash demande le nouveau vocabulaire au serveur (6ᵉ application de la
règle d'unicité) et ne propose que des **switchs** après ce verbe : `completion-bench.sh` § L22,
58 assertions.

### 2026-08-11 — Épisode 6 : la console enregistrée

La sonde de **D2** : la seule qui voie un démarrage **qui n'atteint jamais le relais**, et la
seule que l'invité ne puisse pas récrire. Sur option (`--console-log`, implicite en `--exam`), la
sortie du processus UML est enregistrée dans `<projet>/<nom>-console.log` — à côté du journal
d'un switch, servie par le **même** verbe `log`, sous le nom `console`.

**La mesure a réduit le mécanisme à presque rien**, en retournant la question. Les trois pistes du
plan supposaient qu'il fallait *ajouter* une console ; un UML en a déjà une : sans argument
`console=`, le noyau écrit sur `stderr0`, c'est-à-dire sur la **sortie d'erreur du processus** —
jusqu'ici `/dev/null`. Rediriger stdout et stderr suffit donc, et **aucun argument n'est ajouté**.
Le premier `console=` explicite, lui, l'éteint (`printk: legacy console [stderr0] disabled`) :
là — et là seulement, c'est-à-dire pour le couple 6.12/systemd qui reçoit un `console=tty0` —
on rend une ligne à la place (`ssl0=null,fd:1` + `console=ttyS0` **en tête**, pour que le dernier
`console=` reste celui qui était là, donc l'xterm de l'étudiant intact).

**Le piège de l'épisode coûte 90 secondes de boot**, et il a été payé en mesure avant de l'être en
production : `systemd-getty-generator` instancie un `serial-getty@ttyS0` sur toute console série
active, lequel `BindsTo` un `dev-ttyS0.device` que UML ne crée jamais — le boot attend
`Job dev-ttyS0.device/start running (…/1min 30s)` puis échoue, ce qui aurait en prime pollué le
`systemctl --failed` du collecteur de l'épisode 2. D'où `systemd.mask=serial-getty@ttyS0.service`,
posé seulement quand l'invité est déclaré systemd ; sous SysV, l'`inittab` de Debian a sa ligne
`ttyS0` commentée (vérifié dans l'image wheezy **sans la monter**, par `debugfs`).

Côté canal, le troisième journal n'a pas coûté un troisième cas : la source à trois cas de
l'épisode 4 est devenue une **liste** portant, pour chaque journal, **la phrase à dire quand le
fichier n'est pas là** — et cette phrase n'est jamais la même (attendre l'invité, démarrer le
composant, ou relancer Marionnet avec l'option ; § 4.6). Aucune méthode nouvelle sur les classes :
le chemin est une fonction du projet et du nom, tous deux déjà connus du serveur. La complétion
Bash n'a **pas** été touchée — `help` publie `logs`, qui en compte maintenant trois : septième
application de la règle d'unicité, la première qui ne coûte rien.

**Le discriminant a dû être changé, et ce qui l'a empêché est une bonne nouvelle** : fabriquer un
couple kernel/image qui ne boote pas n'est plus possible **par le canal** — le remap automatique
de `marionnet-retro-compat-kernels-images` corrige un vieux noyau inutilisable, et un noyau hors
`SUPPORTED_KERNELS` est refusé net (les deux mesurés dans un run qui a échoué exprès). Le banc
coupe donc le courant **en plein boot** : le relais n'a pas eu le temps d'exister, le hostfs ne
porte **aucun** journal, la console porte tout le démarrage.

**165 assertions, 0 échec** au banc complet (`journal-bench.sh`, dont § J12 ; 97 sans UML,
96 dans une session lancée **sans** `--console-log` pour mesurer l'autre refus), et **59** au banc
de complétion. Trois machines trixie ont booté dans ce run avec les trois arguments ajoutés : ni
attente, ni unité en échec, ni régression des épisodes 1-3.

### 2026-08-11 — Épisode 7 : le mode examen réanimé

Le § 2.4 promettait que « la moitié du travail » était faite. La mesure l'a démenti deux fois :
personne n'écrivait `report.html` ni `bash_history.text` — c'était su — **et** l'importateur
lui-même ne pouvait pas fonctionner, puisque `import_file` **lève** sur un fichier absent, en
ouvrant un dialogue d'erreur. Depuis des années, éteindre une machine en mode examen produisait
une exception. Le geste d'import est donc gardé par l'existence de chaque fichier, et il est
**unique** : `machine.ml` et `router.ml` appellent le même, ce qui tranche du même coup
l'asymétrie du § 2.4 (le routeur gagne l'historique et la console).

**L'historique s'écrit en continu, pas à l'arrêt.** Le producteur historique copiait
`/root/.bash_history` depuis un script d'arrêt : un Bash interactif tué pendant un shutdown
n'écrit rien, et l'outil qu'il appelait (`cfg2html`) a disparu des images. À la place, le
prologue dépose `/etc/profile.d/marionnet-journal.sh` (et l'accroche en fin de `/root/.bashrc`),
qui met le `HISTFILE` **dans le hostfs** et ajoute `history -a` au `PROMPT_COMMAND`. Le journal
est à jour à chaque invite, donc lisible **à chaud** — quatrième journal du verbe `log`, nommé
`commands` et non `history`, ce mot étant déjà un **verbe** de la grammaire (huitième application
de la règle d'unicité : la complétion l'a reçu sans être touchée).

**Il est horodaté** (`HISTTIMEFORMAT` → une ligne `#<epoch>` avant chaque commande), et c'est ce
qui permet de fusionner les séances de plusieurs composants en une chronologie. Le `PS1` n'est
pas touché : décision de l'auteur — une horloge dans l'invite ferait croire à l'étudiant que sa
vitesse compte — et de toute façon il n'atteindrait aucun fichier, la session de l'étudiant vivant
sur un device UML que rien ne capture.

**Le rapport est du Markdown**, produit par un script déposé dans le hostfs et accroché à l'arrêt.
Le choix n'est pas cosmétique : en HTML, chaque sortie de commande demanderait un échappement, et
un seul `<` casserait la page ; en Markdown la sortie entre telle quelle dans un bloc à quatre
backticks. Il porte, entre autres, la **section pare-feu** demandée (`iptables -L -vv`, la table
NAT, la forme rejouable `iptables-save`, IPv6, `nft list ruleset`).

**Deux mesures ont été nécessaires pour l'unité systemd**, et chacune a corrigé un plan écrit de
bonne foi : sans `Conflicts=shutdown.target` l'unité n'est jamais arrêtée (donc pas d'`ExecStop`,
donc pas de rapport) ; avec les dépendances **par défaut**, elle est arrêtée mais sans ordre, et
l'invité s'éteint **au milieu** du rapport (mesuré : un fichier coupé net en pleine commande). La
forme qui marche est explicite : `DefaultDependencies=no` + `Conflicts=shutdown.target` +
`Before=shutdown.target umount.target` + `After=network.target`. Rapport complet, 19 sections.

**Deux limites, toutes deux mesurées et toutes deux extérieures à l'épisode.** Les vieilles images
SysV n'ont pas de séquence d'arrêt du tout : leur `inittab` répond au ctrl-alt-del par
`/sbin/halt`, contournement Marionnet délibéré qui court-circuite `/etc/rc0.d` — elles gardent
l'historique et les deux journaux de boot, pas le rapport. Et la seule image de routeur installée
(guignol, 2014, i386/SysV) n'atteint pas son relais sur cet hôte : le bout en bout du routeur est
donc sauté par le banc, qui le dit, tandis que sa console est bel et bien archivée.

**Le piège de l'épisode n'était pas dans le code : `stop` rend la main avant la fin.** L'archivage
est la dernière chose que fait l'extinction ; lire `documents` juste après `stop` donne un
treeview vide, et enchaîner sur `close` ferme le projet sous les pieds de l'archivage — qui ne
trouve alors même plus son répertoire (le premier diagnostic, obtenu en journalisant le listing du
hostfs au moment de l'import). D'où le `wait <c> --state=off`, qui est de toute façon ce qu'un
script doit faire.

**57 assertions, 0 échec** au nouveau banc `exam-bench.sh` (dont 30 sans aucun UML), **165 et 0**
au banc du chantier et **59 et 0** au banc de complétion, après mise à jour des listes de journaux.

### 2026-08-12 — Épisode 8 : le terminal de l'étudiant, enregistré

Question posée : peut-on avoir, en mode examen, **le rendu du terminal** — les commandes *et* leurs
résultats, tels que l'étudiant les voit ? Oui, et le § 4.8 dit par quel bout, après que **trois
mesures** ont écarté la piste qui semblait la meilleure.

La conception a changé **deux fois** sous la mesure, jamais sous le raisonnement :

1. Le plan visait `UML_PORT_HELPER` (la variable existe dans le noyau 6.12.95). Sonde : la
   variable **est** dans l'environnement du processus UML, et le noyau lance quand même
   `/usr/lib//uml/port-helper` en dur — elle appartient au canal `port:`, pas au canal `xterm`.
2. Le repli envisagé était de **vendorer** ce port-helper modifié (`port-helper/` à la racine),
   ce qui aurait aussi, croyait-on, allégé la dépendance `uml-utilities`. Deux mesures ont réglé
   la question : le port-helper ne voit passer **aucun octet** (`objdump -T` : `sendmsg`, `pause`,
   ni `read` ni `write`), donc l'enregistrer supposait de réécrire un `script(1)` en C ; et
   `uml_mconsole` garde de toute façon la dépendance vivante. Le nom retenu au passage,
   `marionnet-port-helper`, est devenu faux et a été refait : `marionnet-terminal-record`.

Ce qui est livré tient dans un script d'une centaine de lignes, deux ajouts OCaml minces et un
filtre : substitution du **premier champ** de `xterm=`, `script(1)` autour du port-helper, trois
valeurs passées par l'environnement du processus UML (d'où le `?environment` de la classe
`process`), 5ᵉ journal `terminal` publié par `help`, et une copie **nettoyée** archivée dans
`documents`.

**Un défaut antérieur est tombé en mesurant** : `import_document` acceptait `~move` sans jamais le
transmettre à `import_file` — tous les imports du mode examen étaient des copies, y compris ceux
de l'épisode 7 qui demandent un déplacement. Corrigé, et les intentions revues explicitement
(rapport et historique **copiés**, pour ne pas faire taire `log … commands` après une extinction ;
seule la copie nettoyée du terminal est déplacée).

Le discriminant est celui qui était prévu, et il tient sans humain pour taper : un témoin écrit
par le scénario sur `/dev/tty0` se retrouve dans `log … terminal` — avec le prompt `login:` que
personne n'a demandé et 131 lignes portant des séquences ANSI — et **jamais** dans
`log … console`, qui porte ttyS0.

**73 assertions, 0 échec** au banc `exam-bench.sh` (section E5 ajoutée), **165 et 0** au banc du
chantier, **60 et 0** au banc de complétion — où le cinquième nom arrive **sans que la complétion soit touchée**, 8ᵉ application de
la règle d'unicité. Deux corrections ont porté sur le **banc**, pas sur le mécanisme : un
commentaire à backquotes dans un heredoc **non quoté** déformait le scénario de mesure, et l'on
n'exige plus une extinction *gracieuse* du routeur qui n'a jamais booté — mesuré isolément, cette
image répond au ctrl-alt-del en 30 s si on la laisse démarrer, mais plus après 240 s d'attente
d'un relais qu'elle n'atteint jamais ; on lui coupe donc le courant, ce qui est le geste juste
pour un invité sans init vivant. Une troisième, dans `journal-bench.sh` : le discriminant de
l'épisode 6 coupe le courant « en plein boot », et 8 s ne l'étaient plus assez sur cette machine —
le relais avait le temps d'écrire. Ramené à 5 s.

### 2026-08-12 — Épisode 9 : la documentation, et le droit de nommer

**Ce que l'épisode a livré** (détail et arbitrage : § 4.9) : le § 11 neuf du guide
`doc-src/scripting/README.md` (« Recipe E — the journals » : le verbe `log`, les cinq journaux et
leurs deux natures, les trois refus, les deux plafonds, `switch-info` en miroir, les options
d'enregistrement), la note utilisateur **`doc-src/exam-mode.md`** pour l'enseignant qui ne pilote
pas Marionnet par script, et deux exemples versionnés — `04-journals.sh` et `05-exam-session.sh` —
joués **tels quels** par les bancs. Sections suivantes du guide renumérotées (11→15), une ancre
interne et un renvoi de `useful-scripts/mrn-check` (« § 12 » → « § 13 ») corrigés en conséquence.

**Le seul point de conception**, et il a été tranché explicitement : la doc **nomme** les cinq
journaux (sans quoi elle n'apprendrait rien : `help` donne la liste, pas *qui écrit quoi*), et le
banc **compare** ce tableau à `.logs` de `help` à chaque passage. La règle d'unicité n'est pas
contournée, elle est appliquée sous une forme neuve : citer, et faire vérifier la citation.

**Ce que la mesure a corrigé.** Écrire l'exemple 05 a montré que `wait <c> --state=off` **ne
suffit pas** pour lire `documents` : la transition d'état précède l'import du mode examen. Le
piège noté à l'épisode 7 était donc plus fin qu'écrit — l'attente de l'état est nécessaire, pas
suffisante. L'exemple attend en plus, de façon bornée, que le treeview se remplisse ; et puisque
l'exemple fait lui-même l'extinction gracieuse de la machine, la section E4b d'`exam-bench.sh` ne
l'éteint plus qu'à la condition qu'elle tourne encore. Deuxième correction, mineure : la table MAC
d'un switch démarré **après** ses machines est légitimement vide (rien n'a traversé depuis), ce
que l'exemple dit désormais au lieu d'afficher une section muette.

**Mesures.** `doc-bench.sh` : **62 assertions, 0 échec** (46 avant l'épisode ; +16, dont le garde
anti-dérive du tableau, les refus de `log` sur un câble et sur un journal absent, et les quatre
tables de `switch-info`). `exam-bench.sh` : **74 assertions, 0 échec** (73 avant), la section neuve
**E6** jouant `05-exam-session.sh` tel quel — et, en contre-épreuve `EXAM=0`, exigeant de lui qu'il
**refuse** (code 2) au lieu de collecter du vide. Le **premier** passage d'`exam-bench.sh` a rendu
2 échecs, tous deux imputables à l'image de routeur de 2014 restée `on` après son `poweroff` (d'où
un `close` expiré) : le même échec s'était déjà produit à l'épisode 8 puis avait disparu sans
qu'une ligne change, et le second passage est vert. Aucune ligne de banc n'a été relâchée pour
l'obtenir.
