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
| **1** | **Prologue injecté** : `marionnet-relay.00-journal` déposé par `make_hostfs_content` ; auto-espionnage du `rc_config` (`set -x`, sortie **et** erreur) vers `/mnt/hostfs/rc_config.log` | machine trixie démarrée **par le canal**, `rc_config` volontairement fautif : le journal côté hôte porte la trace et le code d'erreur, là où **rien** n'apparaît aujourd'hui |
| **2** | **Épilogue collecteur** : `marionnet-relay.zz-collect` dépose `dmesg` et, selon `init_system` (déjà connu de Marionnet, `simulation_level.ml:826`), `journalctl -b` + `systemctl --failed`, sinon un extrait de `/var/log/` | un `systemctl --failed` non vide devient visible côté hôte **sans ouvrir un xterm** ; **et** le même scénario sur une image sysv produit l'équivalent sans erreur |
| **3** | **Le canal lit** : verbe `log` dans `control_server.ml`, publié par `help` (5ᵉ application de la règle d'unicité) | `mrnctl log m1 --tail=20` rend ce que `tail` rend côté hôte ; un nœud sans hostfs reçoit un `bad_argument`, par symétrie avec `wait --ready` |
| **4** | **Switch : ne plus jeter les réponses** du rc (`send_commands_to_vde_switch_ignoring_answers`) | un rc de switch avec une commande VLAN fautive produit une erreur **lisible**, là où il ne produit rien |
| **5** | **Switch : instantané** par la socket mgmt (`port/print`, `hash/print`, `fstp/print`) rendu en JSON | la MAC d'une machine réellement démarrée apparaît dans la table du switch auquel elle est câblée — **et pas** dans celle d'un autre |
| **6** | **Capture de console** (sur option, implicite en `--exam`). Trois pistes à départager : `fd:` sur un descripteur ouvert avant `exec`, `tty:` sur un pty, ou l'xterm lancé sous `script(1)` | une image dont l'`init` est volontairement cassé laisse une trace côté hôte, là où le hostfs reste **vide** |
| **7** | **Réanimer le mode examen** : le prologue produit `bash_history.text` (et `report.html`) ; l'import déjà câblé du § 2.4 cesse d'être mort ; le journal de console rejoint les documents | après extinction propre en `--exam`, le treeview `documents` porte les entrées **et** elles survivent à un cycle sauvegarde/rechargement du `.mar` |
| **8** | **Documentation + exemples exécutables + banc** `journal-bench.sh` : « tous les services démarrent », « tel binaire est en telle version » | les exemples de la doc sont joués **tels quels** par le banc |
| **9** *(opt.)* | Vérificateur à l'exécution : assertions déclaratives, compagnon de `mrn-check` | à concevoir seulement une fois 1→8 opérationnels |
| **10** *(opt.)* | Skill de conception/vérification de TP pour agent | idem |

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
