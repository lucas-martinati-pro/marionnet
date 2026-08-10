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
| **4** | **Switch : ne plus jeter les réponses** du rc (`send_commands_to_vde_switch_ignoring_answers`) | un rc de switch avec une commande VLAN fautive produit une erreur **lisible**, là où il ne produit rien |
| **5** | **Switch : instantané** par la socket mgmt (`port/print`, `hash/print`, `fstp/print`) rendu en JSON | la MAC d'une machine réellement démarrée apparaît dans la table du switch auquel elle est câblée — **et pas** dans celle d'un autre |
| **6** | **Capture de console** (sur option, implicite en `--exam`). Trois pistes à départager : `fd:` sur un descripteur ouvert avant `exec`, `tty:` sur un pty, ou l'xterm lancé sous `script(1)` | une image dont l'`init` est volontairement cassé laisse une trace côté hôte, là où le hostfs reste **vide** |
| **7** | **Réanimer le mode examen** : le prologue produit `bash_history.text` (et `report.html`) ; l'import déjà câblé du § 2.4 cesse d'être mort ; le journal de console rejoint les documents | après extinction propre en `--exam`, le treeview `documents` porte les entrées **et** elles survivent à un cycle sauvegarde/rechargement du `.mar` |
| **8** | **Documentation + exemples exécutables + banc** `journal-bench.sh` : « tous les services démarrent », « tel binaire est en telle version » | les exemples de la doc sont joués **tels quels** par le banc |
| **9** *(opt.)* | Vérificateur à l'exécution : assertions déclaratives, compagnon de `mrn-check` | à concevoir seulement une fois 1→8 opérationnels |
| **10** *(opt.)* | Skill de conception/vérification de TP pour agent | idem |

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
