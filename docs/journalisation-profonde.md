# Chantier : journalisation-profonde

> **CHANTIER CLOS le 2026-08-15** (ouvert le 2026-08-10, 25 épisodes — 0 à 24). Ce document est
> désormais une **archive durable** : la fiche mémoire a été réduite à ses pièges transverses, et
> le pointeur de `CLAUDE.md` a été retiré. **Résultat au § 8** ; les défauts qui survivent au
> chantier sans lui appartenir ont été **reversés à `docs/TODO.md`** (§ 8.3). Notes destinées aux
> utilisateurs : `doc-src/teacher-guide.md`, `doc-src/exam-mode.md`,
> `doc-src/scripting/README.md` § 11, `doc-src/lab-design-skill.md`.
>
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
| **10** | **Lire un rapport Markdown depuis la GUI** : conversion **interne** (cmarkit, `~safe:true`) puis navigateur au double-clic, et la **source** à un geste — menu contextuel, fenêtre GtkSourceView éditable. Deux défauts antérieurs tombent avec : l'extension perdue à l'import et le lecteur HTML mort (`galeon`), sans quoi le rendu n'irait nulle part (cf. § 4.10) | un double-clic sur le rapport d'un composant, dans le treeview `documents`, le donne à lire **rendu** — **fait** (2026-08-12) |
| **11** | **La page que le navigateur ne pouvait pas lire** : le rendu de l'épisode 10 était écrit dans `/tmp`, invisible d'un navigateur **confiné** (le Firefox snap d'Ubuntu a un `/tmp` privé, et son profil AppArmor exclut les fichiers **cachés** du home). La page n'est plus écrite nulle part : elle est **servie** sur la boucle locale, sous une URL à jeton, le temps qu'un navigateur la prenne (cf. § 4.11) | le double-clic **affiche** le rapport, mesuré fenêtre à l'appui, là où la même page rendait « Erreur de chargement » — **fait** (2026-08-12) |
| **12** | **La course de l'extinction, et le droit d'écrire** : deux machines qui s'éteignent en même temps écrivaient dans le même treeview depuis deux threads (des champs retombaient sur le défaut de leur colonne, « Please edit this ») ; et la source d'un document était éditable **pendant** l'examen. L'import passe par l'acteur, et la fenêtre source est **en lecture seule** sous `--exam` (cf. § 4.12) | l'onglet Documents après extinction de deux machines ne porte plus aucun champ par défaut ; et sous `--exam` la fenêtre source n'a plus de bouton pour valider — **fait** (2026-08-12) |
| **13** | **Les mots du chantier, dans les douze langues** : les 7 `msgid` introduits depuis l'épisode 6 traduits partout, aucun `.ml` touché — et le `Makefile` corrigé, dont l'extraction du POT re-servait en silence l'instantané précédent (cf. § 4.13) | catalogues 375/3 → **382 traduites / 3 non traduites, 0 fuzzy**, et `msgunfmt` rend les 7 chaînes dans les `.mo` installés — **fait** (2026-08-12) |
| **14** | **La capture qui n'attrapait rien sur wheezy** : sur une image de 2013, `rc_config.log` ne portait que son en-tête — le `tee` du prologue passe par une substitution de processus, que bash ouvre par `/dev/fd`, absent au **runtime** sur cette image. Le prologue répare `/dev/fd`, **mesure** la substitution au lieu de la supposer, et se rabat en le disant (cf. § 4.14) | le même scénario fautif que sur trixie laisse, **sur l'image de 2013**, sa trace, sa sortie et son `!! FAILED (status 2)` dans `rc_config.log` — **fait** (2026-08-12) |
| **15** | **Le corpus des TP, et ce que le canal ne sait pas encore prouver** : cinq TP — dont les séances 7 (iptables/NAT) et 10b (IPv6) de l'auteur — écrits en affirmations, puis **mesurés** verbe par verbe sur une session vivante. Aucune fonctionnalité : la spécification de l'épisode 16 (cf. § 7) | chaque affirmation « prouvable » est rejouée par le banc, et chaque « non observable » est accompagnée de la commande qui **échoue** à la prouver — **fait** (2026-08-12) |
| **16** | **Le rapport à la demande** (voie 1 du § 7.6) : le producteur de l'épisode 7 n'attendait qu'un **déclencheur** et un **service** — veilleur déposé dans le hostfs, protocole à trois fichiers, verbe `report`, 6ᵉ journal du même nom. M1, M3 et M4 comblés ; M2 laissé ouvert (cf. § 4.15) | sur la même machine, au même instant, `log m1 rc_config` ne contient **pas** `ip_forward` et `log m1 report` dit `net.ipv4.ip_forward = 1` — **fait** (2026-08-12) |
| **17** | **Le vérificateur déclaratif** `useful-scripts/mrn-verify` : un fichier d'assertions (`.mrv`) contrôlé puis joué contre une session vivante, trois verdicts dont le troisième compte (`SKIP` ≠ `FAIL`), et des **capacités lues dans la grammaire** — compagnon de `mrn-check`, comme un `.mrv` est le pendant d'un `.mrn` (cf. § 4.16) | deux lignes du même fichier, sur la même machine au même instant : `journal m1 rc_config contains ip_forward` **échoue** et `report m1 says … ip_forward = 1` **passe** — **fait** (2026-08-12) |
| **18** | **M2 — exécuter dans un invité** : verbe `exec <composant> <ligne de commande> [--timeout=<s>]` (voie 2 du § 7.6), servi par le veilleur de l'épisode 16 **généralisé** ; **7ᵉ journal** `exec` (ce que le canal a injecté, tenu à part de ce que l'étudiant a tapé) ; et la famille `reaches` de `mrn-verify` devient vivante (cf. § 4.17) | sur la même session, au même instant : `reaches m1 h3` **PASS**, puis h3 éteinte **FAIL**, alors que le rapport de m1 n'a pas bougé — un rapport décrit un **état**, jamais une **accessibilité** — **fait** (2026-08-12) |
| **19** | **Le skill de conception de TP**, pour un agent IA quelconque : `doc-src/lab-design-skill.md` (anglais, livré avec la doc) + un wrapper mince `.claude/skills/marionnet-lab-design/`. Il nomme les 43 verbes — décision de l'auteur : **citer, et faire vérifier la citation** — mais ne recopie **aucune** syntaxe (cf. § 4.18) | son TP d'exemple est **joué** : le `.mrn` linté et envoyé, le corrigé rendant 13 PASS / 1 FAIL — et le FAIL est exactement l'assertion que le § 7.4 réserve à la session d'examen — **fait** (2026-08-12) |
| **20** | **Le routeur mesuré** : tout ce que le chantier n'avait jamais pu jouer faute d'une image de routeur qui démarre (§ 6, liste close du 2026-08-13), rejoué une fois `79c25dd` réparé le choix du noyau — et le **défaut** que ce rejeu a fait apparaître : trois scripts déposés dans l'invité testaient la **présence** de `timeout(1)` là où seule sa **capacité** compte (cf. § 4.19) | sur le même routeur, le même rapport : **17** sections « can't execute » avec le code précédent, **0** avec le correctif — et le journal `exec` **nomme** la raison de son repli — **fait** (2026-08-13) |
| **21** | **Le guide de l'enseignant** (anglais) `doc-src/teacher-guide.md` : le fil qui va de l'énoncé à la note, un exemple **par commande** — des **gestes joués**, pas des citations —, un TP réel complet et noté en `--exam` (`doc-src/labs/session-7/`), et un § « concevoir et noter un TP avec un agent IA » écrit du côté de l'humain (cf. § 4.20) | la couverture est mesurée **par l'exécution** : le banc rejoue chaque ligne du § 4 et compare les verbes **appelés** à ceux que `help` publie, dans les deux sens ; et le TP joué deux fois rend 14/0 puis 12/2, l'état et l'expérience basculant, la trace non — **fait** (2026-08-13) |

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

### 4.10 Ce que l'épisode 10 a livré (et pourquoi la conversion est interne)

Neuf épisodes ont produit de la matière, un canal pour la lire et une doc pour l'expliquer. Il
restait un endroit où le chantier ne tenait pas sa promesse : **l'interface**. Le rapport de fin
de session est du Markdown (épisode 7, et pour une bonne raison : son producteur est du Bash dans
un invité minimal), et un double-clic dans le treeview `documents` l'ouvrait dans
`MARIONNET_TEXT_EDITOR` — lisible, non rendu.

**Le point de conception est le déterminisme, et il ne se voit qu'en pensant à la notation.** Le
premier plan cherchait un convertisseur *sur l'hôte* — `pandoc`, `cmark`, `markdown_py` — avec
repli sur l'éditeur de texte. C'est le réflexe de ce dépôt (un lecteur externe par format, réglé
par variable d'environnement), et il est faux ici pour deux raisons :

- **la même archive rendrait différemment selon la machine** qui l'ouvre, et rien sur la page ne
  dirait laquelle a servi. Pour un document sur lequel une note peut reposer, c'est un défaut, pas
  un détail ;
- **`report.md` est écrit dans l'invité**, donc sur une machine que l'étudiant contrôle. Avec
  `pandoc` ou `markdown_py`, le HTML brut passe tel quel : un `<script>` déposé dans le rapport
  s'exécuterait dans la page du correcteur.

D'où `cmarkit` (ISC, Daniel Bünzli, **aucune dépendance**) lié au binaire : `Doc.of_string
~strict:false` (les tableaux du rapport en dépendent) puis `Cmarkit_html.of_doc ~safe:true`.
L'échappatoire demeure — `MARIONNET_MARKDOWN_TO_HTML`, une commande qui lit le Markdown sur son
entrée standard — mais elle est **explicite** : le rendu plus riche devient une décision de
l'exploitant, avec ce qu'elle coûte, dit dans `marionnet.conf`. L'enveloppe de la page (doctype,
charset, feuille de style sobre) est la nôtre **quel que soit** le convertisseur : un convertisseur
qui oublie le charset ne peut pas transformer les accents d'un rapport français en mojibake.

**Ce que la mesure a retourné** : `~safe:true` ne fait pas ce que le plan supposait. Il n'échappe
pas le HTML brut, il le **jette**, en laissant un commentaire (`<!-- CommonMark HTML block
omitted -->`) — invisible dans un navigateur. Le correcteur aurait lu un rapport troué **sans le
savoir**. L'omission est donc remplacée par une ligne visible, et ce que l'invité a écrit reste
atteignable par la vue *source*. Le motif de remplacement suit un rendu que la bibliothèque
documente comme instable : s'il change, on retombe sur le commentaire invisible (dégradation, pas
casse) et le banc rougit — raison pour laquelle il assert sur le **marqueur visible**.

**Deux défauts antérieurs, tous deux nécessaires au discriminant.** (1) `import_file` copiait le
document vers `document-XXXXXX`, **sans extension** : à l'affichage, rien ne distinguait un
rapport Markdown d'un texte, la colonne `Format` disant « text » pour les deux — délibérément,
depuis l'épisode 7, pour qu'aucune valeur de format neuve n'atteigne un `.mar` (D5). L'extension
est désormais conservée (filtrée : elle finit dans une ligne de commande), le format persisté ne
bouge pas, et un `.mar` antérieur — dont les documents n'ont pas d'extension — garde exactement le
comportement qu'il avait. (2) `MARIONNET_HTML_READER` valait `galeon` dans `etc/marionnet.conf`
*et* dans le code : un navigateur mort vers 2010. Or `display` lance `«lecteur 'fichier' &»`, donc
le shell sort 0 quoi qu'il arrive et un lecteur absent ne produit **rien**, en silence. Les
lecteurs sont maintenant vérifiés (`UnixExtra.is_executable`, sur le **premier mot** pour laisser
passer les options) avec repli sur `xdg-open` et quelques usuels — ce qui répare aussi le
`marionnet.conf` déjà installé de qui n'y a jamais touché.

**Le choix rendu/source.** Demandé par l'auteur pendant le plan, et livré dans le même épisode
parce que tout existait : `Gui_source_editing.window` (GtkSourceView3 + `Egg`, employée jusqu'ici
pour les fichiers de configuration), `markdown.lang` présent dans gtksourceview-3.0, et un menu
contextuel de treeview qui prend un **prédicat**. Deux gestes plutôt qu'une boîte de dialogue à
chaque ouverture : double-clic = lire (le rendu), menu contextuel = la source, éditable. L'entrée
n'apparaît que sur une ligne Markdown. L'édition écrit le document du projet — ouvrir, écrire,
refermer, les documents importés étant posés en lecture seule — et marque le projet modifié en
repassant par l'acteur, la fenêtre étant créée depuis le thread principal et l'attente de l'`Egg`
depuis un thread à part (le motif de `gui_bricks.ml:990`). Fermer la fenêtre **annule**, contrairement
à l'éditeur de configuration : celle-ci écrit un fichier, une fermeture par mégarde ne doit rien
committer. Et sur le fond : rendre un document du `.mar` modifiable n'enlève aucune garantie — le
`.mar` est de toute façon entre les mains de l'étudiant, et `exam-mode.md` dit depuis l'épisode 9
quels journaux sont falsifiables ; ce que l'édition apporte, c'est l'**annotation par le
correcteur**.

**Le banc mérite un mot**, parce que sa méthode est neuve dans ce chantier : le rendu vit dans un
fichier qui dépend de lablgtk, donc aucune stanza `(tests)` ne peut le lier, et le geste qui le
déclenche est un double-clic. Plutôt que de **paraphraser** le code (un banc paraphrasé ment dès
la première divergence), `markdown-bench.sh` **extrait** le module `Markdown_rendering` du fichier
source, lui donne une doublure de ses trois dépendances et le compile : ce sont les vraies lignes
qui répondent. Reste hors de sa portée le câblage GUI lui-même — geste humain, joué à la main.

**Une dépendance de build s'ajoute** : `cmarkit`, la troisième après `yojson` et `base64`, et la
seule sans paquet Debian/Ubuntu (vérifié le 2026-08-12). Le `Makefile` le dit à l'endroit où le
chantier `modernisation-installation-marionnet` viendra le lire.

### 4.11 Ce que l'épisode 11 a livré (et le navigateur qui ne voit pas `/tmp`)

L'épisode 10 était livré, committé, et son banc vert. Il restait le geste que rien n'automatisait
— le double-clic. Joué (avec `xdotool`, que l'auteur venait d'installer), il a **échoué** : le
rapport s'ouvrait bien dans Firefox, sur *« Erreur de chargement de la page »*.

**La cause n'est pas dans le rendu, elle est dans l'emplacement.** Le Firefox d'Ubuntu est un
**snap**, et `snap-confine` donne à chaque snap un `/tmp` **privé** : la page écrite dans le
`/tmp` de l'hôte n'existe tout simplement pas pour lui. Son profil AppArmor est explicite sur le
reste — `owner @{HOME}/[^s.]**`, c'est-à-dire le home **moins ses fichiers cachés** (le
commentaire du profil dit « to prevent reading dotfiles ») : `~/.marionnet/` aurait échoué
pareillement.

**Le premier correctif a été refusé, et à raison.** Il posait la page dans un répertoire **non
caché** du home (`~/marionnet-rendered/`) — le seul endroit qu'un navigateur deb, snap ou flatpak
peuvent tous lire. C'est céder deux fois : créer un répertoire visible chez l'utilisateur pour un
fichier **recalculé à chaque lecture**, et le faire à cause d'un choix d'empaquetage d'une
distribution. L'auteur a demandé d'autres pistes ; quatre ont été mises sur la table (écarter les
navigateurs confinés ; servir la page ; rendre le Markdown dans une fenêtre Gtk+ ; refuser
explicitement), et c'est **servir la page** qui a été retenu.

**Ce qui est livré : la page n'est écrite nulle part.** Elle est servie sur `127.0.0.1`, sur un
port éphémère, sous un chemin qui est un **jeton de 128 bits** tiré de `/dev/urandom`, par le
serveur d'ocamlbricks (`Network.stream_inet4_server`, `~no_fork:()` — jamais forker une GUI —
`~range4:"127.0.0.1/32"` : seule la boucle locale peut se connecter). Le lecteur reçoit une URL
au lieu d'un chemin, ce que la ligne de commande de `display` accepte sans changer d'une virgule.
Tout navigateur, confiné ou non, a le droit d'atteindre la boucle locale : c'est la seule réponse
qui ne dépende pas de la façon dont la machine empaquette ses logiciels — et il ne reste **rien**
derrière, ni dans le home, ni dans `/tmp`.

Le serveur se retire **de lui-même** : cinq secondes après que la page a été prise (un navigateur
peut la demander deux fois — un rechargement, une favicon), et de toute façon au bout de deux
minutes. Un rapport d'examen ne reste donc pas lisible depuis `localhost` pendant toute la
session. Le repli, si la boucle locale n'est pas disponible, reste le fichier temporaire de
l'épisode 10 : jamais rien plutôt qu'une fenêtre en moins.

**Ce que l'épisode dit de la méthode.** Le banc de l'épisode 10 ne pouvait pas voir ce défaut : il
vérifiait que la page **existe** et qu'elle est **hors du projet**, ce qui était vrai. Ce qu'il ne
pouvait pas vérifier, c'est qu'un **autre programme, confiné, y accède** — et aucune assertion sur
notre propre processus ne l'aurait montré. C'est le geste humain, joué une fois, qui l'a dit. La
mesure a été rendue au banc ensuite (la forme de l'URL, la page servie, le 404 sans le jeton, le
type MIME, le retrait automatique, et le home resté propre), mais l'ordre compte : **le banc ne
remplace pas le premier passage réel**.

**Mesuré, fenêtre à l'appui** : le double-clic sur *Report on m1* affiche le rapport **rendu**
(titres, listes, blocs de code) ; le menu contextuel n'offre l'entrée *source* que sur la ligne
Markdown ; la fenêtre GtkSourceView colore bien le Markdown ; `Valider` écrit l'annotation dans le
document du projet (accents compris) et **rétablit** la lecture seule ; `Annuler` ne change pas un
octet. Le banc de l'épisode lie désormais le **vrai** ocamlbricks construit par dune, au lieu
d'une doublure d'`UnixExtra` : le module extrait s'appuie sur `Network`, il n'y a plus rien à
simuler.

### 4.12 Ce que l'épisode 12 a livré (la course, et qui a le droit d'écrire)

Deux défauts rapportés par l'auteur après un `--exam` réel sur un projet à deux machines.

**(1) Des champs retombés sur le défaut de leur colonne.** L'onglet Documents montrait des lignes
portant « Please edit this » — la valeur par défaut d'une colonne — là où l'import venait de poser
un titre, un type ou un auteur, et l'auteur valait tantôt « - », tantôt le nom de l'utilisateur
(celui que `import_document` pose avant que `import_report` ne le remplace). Nondéterministe, donc
une **course** : `import_exam_documents` s'exécute dans le thread d'**extinction** de chaque
machine, et éteindre un laboratoire les éteint **toutes à la fois** — deux séquences
`add_row`/`set_row_*` s'entrelaçaient dans un `GtkTreeStore` et une forêt que rien ne protège.

Le correctif est la règle du dépôt, appliquée là où elle manquait (`docs/refonte-automate-composants.md`) :
**toute mutation Gtk+ appartient au thread principal**. C'est le **geste entier** qui passe par
l'acteur, et non chaque ligne : ce qui ne doit pas s'entrelacer est la séquence, pas l'appel isolé.
`apply_extract` bloque jusqu'au bout, ce dont l'appelant a besoin — juste après, l'extinction
détruit le composant et le hostfs d'où les fichiers sont copiés.

**Honnêteté du banc** : `exam-race-bench.sh` lance les deux extinctions en parallèle **par le
canal** et vérifie qu'aucun champ n'est défaillant, mais il ne **reproduit pas** la course — mesuré,
les deux archivages tombent à ~5 s d'écart et le banc passe **aussi sans le correctif** (vérifié en
le désactivant). Le déclencheur observé est le bouton **« Tout arrêter »** de la GUI, qui les éteint
vraiment d'un coup. Le banc vaut donc comme **non-régression** ; la justification du correctif est
le code et la discipline, pas ce passage.

**(2) L'étudiant pouvait éditer sa copie.** L'épisode 10 avait donné à la fenêtre source le droit
d'écrire — pensé pour le **correcteur** qui annote un rapport. En mode examen, c'est l'étudiant qui
est devant l'écran : lire ce que sa session a produit est légitime, le réécrire ne l'est pas. La
fenêtre `Gui_source_editing` reçoit donc un `?read_only` (vue non éditable, **un seul** bouton, qui
ferme — pas un `OK` grisé, qui laisserait croire qu'on pourrait valider en sachant s'y prendre), et
le treeview le passe quand `Initialization.are_we_in_exam_mode`. L'entrée de menu change de nom en
conséquence (« Show the source » / « Show and edit the source ») : le libellé dit ce que le geste
fait **ici**. Hors examen — l'enseignant, un script, un agent qui rouvre le projet — rien ne change.

### 4.13 Ce que l'épisode 13 a livré (les mots du chantier, dans les douze langues)

Le § 6 signalait un défaut visible : l'entrée de menu de l'épisode 10 s'affichait **en anglais au
milieu d'un menu français**. Le code n'était pas en cause — il appelle `s_` depuis le premier jour ;
c'est le **catalogue** qui ne connaissait pas ces mots. Sept `msgid` exactement, tous introduits par
ce chantier : `Console`, `Console of `, `Terminal`, `Terminal of ` (les colonnes *Type* et les
titres des documents archivés aux épisodes 6-8), `Source of ` et les **deux** libellés de menu de
l'épisode 12 — deux, parce que le libellé dit ce que le geste fait *ici* (lecture seule sous
`--exam`, ou édition).

**Le défaut qui a failli faire croire à un épisode sans objet.** La première régénération du POT n'a
produit **aucun diff**, alors que sept chaînes manquaient. La cible `gettext-all-ml-pot-files`
prend un instantané des sources par **liens durs** (`cp -l`) dans `_build/pot/…` — et `cp -l`
**échoue** quand la cible existe déjà. Le second passage extrayait donc, en silence, l'instantané du
passage précédent : ici, une copie de `treeview_documents.ml` datée du 9 août (13 808 octets contre
44 093). Le `Makefile` **efface** désormais ce répertoire avant de le refaire — ce qui règle du même
coup le `.pot` d'un module supprimé, que `msgcat` aurait continué de concaténer. C'est la
même famille de piège que « dune ne voit pas à travers camlp4 » (épisode 1) : un outil qui garde
l'ancien résultat **sans rien dire**.

**Ce qui a guidé les traductions.** Les chaînes sœurs du même treeview étaient déjà traduites
partout (`Report`, `Report on `, `History`, `History of `, `Display this document`) : elles donnent
le registre langue par langue — l'infinitif et le point final en allemand, la nominalisation en
grec, le génitif en roumain. Deux écarts assumés :

- **Le turc prend la forme « X : »** (`Konsol: `, `Terminal: `, `Kaynak: `). Le turc est
  postpositionnel — *« la console de m1 »* s'y dit `m1 konsolu` — et le code **concatène un
  préfixe** ; aucune traduction préfixée n'y est grammaticale. Les traductions historiques s'en
  tirent par des périphrases bancales (`History of ` → `Tarihçesi alınan kayıt `) ; le deux-points
  est honnête, court et lisible.
- **`es`/`pt`/`pt_BR` disent « code source »**, pas « fuente/fonte » seul, qui désigne aussi une
  **police de caractères**. Le document rendu est un `report.md` : c'est bien une source.

**Ce que l'épisode ne fait pas.** Les **trois** chaînes non traduites qui restent dans les douze
catalogues sont les longs textes d'aide de `world_bridge` : elles appartiennent à
`modernisation-world-bridge`, qui les a introduites, et y sont renvoyées. L'invariant « on ne
supporte que des catalogues complets » n'est donc pas encore rétabli — mais il ne l'était pas non
plus avant cet épisode, et plus une seule des chaînes manquantes n'est de notre fait.

### 4.14 Ce que l'épisode 14 a livré (et l'`exec` qui échouait en silence)

Le § 6 portait, depuis l'épisode 7, une ligne « à instruire » : sur `debian-wheezy-08367`,
`rc_config.log` ne portait **que ses trois lignes d'en-tête**, alors que `boot.log` — écrit par le
même épilogue, sur la même image — était complet. Un trou dans le livrable de l'épisode 1, sur la
seule vieille image qui boote encore.

**Le symptôme découpait le prologue en deux**, et c'est ce découpage qui a servi de sonde :
l'en-tête est écrit par une redirection **explicite** (`>> "$log"`), tout le reste dépend de la
redirection **globale** posée juste après. Ce qui manquait était exactement ce qui vient après
cette ligne — y compris la ligne `# capture:` qu'elle fait suivre.

**Mesure.** Une sonde a été posée dans le `rc_config` du scénario — pas dans un fichier du dépôt —
et surtout **écrite par redirection explicite vers un fichier à nous** : sur cette image la console
de l'invité part dans un xterm et non dans le processus UML, si bien que « ce qui n'est pas
capturé » ne se retrouve **nulle part**, pas même dans le journal de console de l'épisode 6. Ce
détour est ce qui a rendu la panne visible. Elle a rendu, d'un seul boot :

```
PROBE: bash=[4.2.37(1)-release] flags=[hxBE]     <- set -x EST actif : le prologue est allé au bout
PROBE: journal=[/mnt/hostfs/rc_config.log] teepid=[1102]
PROBE: fd1 -> pipe:[756]                          <- DEUX pipes distincts : le 2>&1 n'a pas eu lieu
PROBE: fd2 -> pipe:[760]
PROBE: /dev/fd -> /dev/fd ; ls: cannot access /dev/fd: No such file or directory
udev on /dev type tmpfs (rw,mode=0755)
PROBE: procsub KO (… line 13: /dev/fd/62: No such file or directory)
```

**Cause racine.** `tee` est atteint par une **substitution de processus**, et bash implémente
celle-ci en ouvrant `/dev/fd/<n>` **dans le shell appelant**. Or l'image de 2013 n'a pas `/dev/fd`
quand elle **tourne** : le lien symbolique livré *dans* l'image (vérifié par `debugfs`, sans la
monter) est **masqué** par le tmpfs monté sur `/dev` au boot, et l'init de cette image ne le remet
pas (Debian le fait dans `mountdevsubfs.sh`). Donc `exec > >(tee -a "$log") 2>&1` **échoue** — et il
échoue **en entier**, `2>&1` compris, les redirections s'appliquant de gauche à droite : le shell
garde ses descripteurs d'origine et **poursuit**. D'où les trois symptômes réunis : le `set -x`
« fonctionne » (il trace, mais vers l'ancien descripteur), les deux pipes sont **distincts**, et le
journal ne garde que ce qui a été écrit avant.

Corollaire de méthode : la garde `type -p tee` **ne posait pas la bonne question**. `tee` est bien
là (`/usr/bin/tee`) ; c'est la substitution qui ne s'ouvre pas. Une garde qui teste un **moyen**
plutôt que la **capacité** ne garde rien.

**Correctif** (un seul fichier, `bin/scripts/marionnet-relay.00-journal.sh`), dans l'ordre :

1. **remettre `/dev/fd`** s'il manque (`ln -s /proc/self/fd /dev/fd`, gardé par `[[ ! -e /dev/fd ]]`
   et par l'existence de `/proc/self/fd`) — `/dev` est un **tmpfs**, donc aucune image, ni même le
   COW, n'est écrite, et ce n'est que la remise en place d'un élément standard du boot que cet init
   saute ;
2. **mesurer** la substitution au lieu de la supposer : `( exec 9> >(cat >/dev/null) )` dans un
   sous-shell. C'est cette mesure qui est la vraie garde — elle couvre toutes les causes, pas
   seulement celle-ci ;
3. **le dire** : la branche de repli nomme sa raison (`# capture: journal only (no usable /dev/fd
   in this image), the console keeps nothing`), au lieu du `no tee in this image` unique et parfois
   faux.

L'épilogue n'a **pas** bougé : son contrat (`__mrn_journal_tee_pid` vide ou non) est inchangé.

**Mesuré après correctif**, sur la même image et par le même scénario fautif : `# capture: tee
(console and journal)` — la réparation suffit, on ne se rabat pas —, un journal de **39 lignes** au
lieu de 3, la trace `set -x` du scénario, sa sortie standard, et
`!! FAILED (status 2): ls /journal-bench-no-such-path`. Le banc `journal-bench.sh` passe de 165 à
**171 assertions, 0 échec** (les 6 neuves sont dans le bloc J8, celui de l'image sysv réelle) ;
`exam-bench.sh` reste à **74 assertions, 0 échec** — le prologue porte aussi l'historique de
l'épisode 7.

**Ce que l'épisode ne fait pas.** Il ne touche à aucune image, n'ajoute ni verbe, ni journal, ni
option, et ne crée que le lien `/dev/fd` **manquant** — pas `/dev/stdin`, `/dev/stdout`,
`/dev/stderr`, dont personne ici n'a besoin.

### 4.15 Ce que l'épisode 16 a livré (et le producteur qui n'attendait qu'un déclencheur)

L'épisode 15 avait rendu quatre manques (§ 7.3) et trois voies chiffrées pour les combler
(§ 7.6). Celui-ci joue la **voie 1**, la moins intrusive, et son argument est entier dans le
constat de l'épisode précédent : **il ne manquait ni producteur ni format**. `marionnet-report.sh`,
écrit à l'épisode 7, porte déjà exactement ce qu'un correcteur veut lire — interfaces réelles,
tables de routage v4 *et* v6, voisinage, `ip_forward`, pare-feu sous forme rejouable. Il lui
manquait un **déclencheur** (il ne s'exécutait qu'à l'arrêt) et un **service** (`log … report`
refusait, la liste des journaux était fermée à cinq). L'épisode ajoute l'un et l'autre, et rien
de plus : aucune ligne de rapport n'est réécrite.

**Le veilleur, et le protocole à trois fichiers.** `bin/scripts/marionnet-report-watch.sh` est
déposé dans le hostfs comme ses aînés, et l'épilogue le démarre en arrière-plan à la fin du boot.
Il attend un fichier-drapeau, produit, publie, et répond — le hostfs restant le seul chemin de
retour (D1 : aucune image reconstruite) :

| Fichier | Écrit par | Effacé par |
|---|---|---|
| `report.request` | l'**hôte** (verbe `report`) | l'**invité**, dès qu'il le voit |
| `report.md` | l'**invité**, en **renommant** `.report.md.part` | personne |
| `report.done` | l'**invité**, après le renommage (`status=… epoch=… lines=…`) | l'**hôte**, avant de poser une requête |

Deux détails de ce tableau ne sont pas du zèle. Le **renommage** : le canal sert `report.md`
*pendant* que l'invité tourne, donc un lecteur ne doit jamais pouvoir tomber sur un rapport à
moitié écrit — d'où un fichier temporaire et un `mv`. Et l'**effacement préalable** de
`report.done` par l'hôte : c'est lui, et lui seul, qui rend la réponse **prouvablement fraîche**
— un fichier qui réapparaît a été écrit après la requête. L'invité l'efface **aussi**, avant de
produire, pour le cas où un client mort aurait laissé le sien.

**Pourquoi l'épilogue, et pas le prologue.** Le veilleur doit **survivre au relais**, et les deux
systèmes d'init ne l'entendent pas de la même façon : sous systemd le relais est un script LSB
lancé par une unité générée, et un enfant en arrière-plan meurt avec le groupe de contrôle de
l'unité. D'où deux branches, décidées par l'**invité** comme partout dans ce fichier depuis
l'épisode 2 — une unité `marionnet-report-watch.service` écrite dans `/run` (le motif déjà
éprouvé du crochet d'arrêt), ou `setsid … &`. Et d'où le placement : à la fin de l'épilogue,
**après** que la capture de l'épisode 1 a été refermée. Un veilleur lancé plus tôt hériterait des
descripteurs redirigés vers le `tee` et **retiendrait le tuyau ouvert pour la vie de la machine** ;
il hériterait aussi du `set -x` et du trap `ERR`, qu'il dépose donc explicitement en tête.

**Le verbe, et le nom qu'il partage avec le journal.** `report <component> [--timeout=<s>]` est le
troisième d'une famille : `log` sert ce qui a été **écrit**, `switch-info` demande à un switch ce
qu'il **sait**, `report` demande la même chose à un **invité**. Sa réponse dit *que* le rapport a
été pris — jamais son contenu, qui est un journal et se lit par `log <c> report` : une chose est
servie à un seul endroit. Le verbe et le journal portent le **même mot**, ce qui semble contredire
la règle qui avait imposé `commands` plutôt que `history` à l'épisode 7 — mais la règle disait
« un mot, un sens » : `history` était déjà un verbe désignant **autre chose** (le treeview des
états), alors qu'ici le verbe et le journal nomment **une seule et même chose**, l'un la
produisant, l'autre la servant.

**Le producteur dit désormais *quand* il a été pris.** Deux variables d'environnement, toutes deux
avec le défaut de l'épisode 7 : `MARIONNET_REPORT_OUT` (le fichier temporaire du veilleur) et
`MARIONNET_REPORT_WHEN`, qui change le titre et l'encart — `on-demand` ou `shutdown`. Ce n'est pas
cosmétique : un **instantané ne vaut que ce que dit sa date**, et un correcteur qui lit une archive
doit savoir s'il regarde l'état d'une session en cours ou celui qu'elle a laissé en mourant.

**Les discriminants**, tous deux venus des pièges que l'épisode 15 avait mesurés :

1. le rc du banc met `ip_forward` à 1 **par une redirection**. La **trace** ne porte que `echo 1`
   — `set -x` ne trace pas les redirections (§ 7.4) — et le **rapport** porte
   `net.ipv4.ip_forward = 1`. Les deux réponses viennent du même verbe `log`, sur la même machine,
   au même instant : c'est la démonstration en une ligne de ce que l'épisode ajoute. Une trace
   prouve ce qui a été **appelé**, un rapport ce qui **est** ;
2. le rapport porte une adresse `fe80::` **fabriquée dans l'invité**, que le treeview `ifconfig`
   ignore et doit continuer d'ignorer (il porte le *déclaré*) — M4, sur la mesure même qui l'avait
   établi.

**Ce que l'épisode ne fait pas, et le dit.** **M2 reste ouvert** : rien n'exécute de commande dans
un invité, donc aucune affirmation de **connectivité** n'est prouvable. C'était la voie 2 du
§ 7.6 (`exec <c> <cmd>`), qui ferait du canal un exécuteur à l'intérieur des invités — un
changement de nature, à trancher pour lui-même. Le banc mesure ce manque **en creux** (aucun verbe
publié nommé `exec`, `run`, `shell`, `ssh`), pour qu'il ne puisse pas tomber par inadvertance.

**Bénéfice de bord.** Le rapport ne dépend plus de l'extinction, donc il redevient atteignable sur
les vieilles images **SysV**, dont le § 4.7 disait qu'elles n'ont pas de séquence d'arrêt (leur
`inittab` répond au ctrl-alt-del par `/sbin/halt`). La limite reste entière pour le rapport *de
fin* ; elle tombe pour le rapport *à la demande*.

### 4.16 Ce que l'épisode 17 a livré (et le verdict qu'il fallait ne pas rendre)

L'épisode 15 avait écrit cinq TP en affirmations ; l'épisode 16 avait donné à ces affirmations la
matière qui leur manquait. Restait à les **écrire quelque part** — et le tableau du § 4 réservait
cette case au vérificateur, que l'épisode 16 a occupée en livrant autre chose. C'est cet épisode.

**Pourquoi un fichier, et pas un script.** Un corrigé écrit en bash marche une fois, pour un TP,
et personne ne le relit. Surtout, il rejoue à chaque fois les deux pièges que le § 7.4 a mesurés :
la trace `set -x` **ne porte pas les redirections** (donc chercher `ip_forward` dans un journal de
démarrage ne prouve rien), et un échec absorbé par `|| true` **ne laisse aucune trace**. Un fichier
d'assertions les fige une fois pour toutes : `journal … contains` et `report … says` sont deux
assertions **différentes**, et l'outil qui les sert sait laquelle prouve quoi.

`useful-scripts/mrn-verify` est donc au `.mrv` ce que `mrn-check` est au `.mrn`, avec la même
mécanique et pour les mêmes raisons : il **contrôle d'abord, joue ensuite** (un fichier avec une
faute de frappe en ligne 12 ne doit pas avoir produit onze verdicts et un rapport qu'on lira comme
complet), et il ne détient **aucune** copie de la grammaire.

**Trois verdicts, et c'est le troisième qui compte.** `PASS` et `FAIL` vont de soi ; `SKIP` dit que
le canal **n'a aucun moyen de savoir**, et nomme lequel. La distinction n'est pas du zèle : un
vérificateur qui répond « faux » là où il devrait répondre « je ne sais pas » recale un étudiant
pour une limite de l'outil. `reaches m1 intrus` — l'affirmation dont trois des cinq TP du § 7.1 ont
besoin — n'est servie par personne aujourd'hui (M2), et c'est ce qu'elle répond :

    SKIP  reaches m1 intrus
          this Marionnet publishes no `exec' verb: the channel offers no way to know

**La capacité vient de la grammaire.** C'est la 10ᵉ application de la règle d'unicité du chantier
frère, sous une forme neuve : jusqu'ici on demandait au serveur son **vocabulaire** (les verbes,
les journaux, les tables) ; ici on lui demande ce que l'outil **sait faire**. Une famille
d'assertions déclare le verbe qui la porte, et ce verbe est cherché dans ce que `help` publie —
d'où deux conséquences. La phrase ci-dessus n'est pas une constante : le jour où l'épisode 18
publiera `exec`, le même fichier commencera à être répondu **sans qu'une ligne de `mrn-verify`
change**. Et c'est mesurable **sans UML** : le même `.mrv`, contrôlé contre l'instantané complet de
`help` puis contre le même instantané amputé du verbe `report`, ne dit pas la même chose.

**Le langage est fermé, et aucune de ses neuf familles n'est inventée** : chacune vient d'une ligne
du § 7.5, donc d'une affirmation d'un TP réel. `reaches` y est écrite **d'avance** — l'auteur a
tranché M2 en rouvrant l'épisode — plutôt que d'être ajoutée après coup : un TP peut déjà dire ce
qu'il veut dire, quitte à ce que la ligne soit sautée en attendant. `--strict` fait de tout `SKIP`
un échec, pour qui veut un TP **entièrement** prouvable.

**Quatre corrections par la mesure**, dont trois ont mis en défaut le plan ou le banc, jamais le
mécanisme :

1. **Sous `set -e`, une fonction d'analyse qui rend le statut de sa dernière garde arrête tout** —
   en silence. Une ligne fautive (`cable c1 m1eth0 …`) faisait `return` avec un statut non nul,
   la boucle de lecture appelant cette fonction comme une commande simple : le fichier n'était
   plus lu au-delà, et le rapport paraissait seulement **plus court**. Le banc l'a vu parce qu'il
   compte les erreurs attendues ; un humain aurait lu quatre diagnostics sur cinq sans sourciller.
   Même famille que les pièges de l'épisode 14 : ce n'est pas le mécanisme qui ment, c'est
   l'absence qui ne se voit pas.
2. **Les entrées d'une table de switch ne sont pas plates** : les ports d'un VLAN sont une *liste
   d'objets*. D'où des clés atteintes par **chemin pointé** (`ports.port=3`), obtenues en aplatissant
   l'entrée — les index de liste tombent, les noms restent. Aucun nom de champ n'est écrit dans
   l'outil, et une clé que le switch n'a pas est rendue **avec la liste de celles qu'il a** : le
   message apprend le vocabulaire au lieu de le faire deviner.
3. **Les titres du treeview `documents` passent par gettext** (piège déjà connu) : l'assertion
   `documents <c> has <motif>` s'appuie donc sur le **nom du composant**, qui n'est pas traduit.
4. **Un `rc-set` sur un switch déjà démarré une fois est ignoré au démarrage suivant** — défaut du
   dépôt, découvert en fabriquant le banc, consigné au § 6 et laissé là : il ne concerne pas le
   vérificateur, et le corriger en passant aurait mélangé deux mesures.

**Le discriminant** est en deux lignes du même fichier, sur la même machine, au même instant :

    journal m1 rc_config contains ip_forward     → FAIL
    report  m1 says ~ net[.]ipv4[.]ip_forward *= *1  → PASS

La configuration a bien tourné ; c'est la **trace** qui ne peut pas le dire. Un corrigé écrit sur
la première ligne recalerait un étudiant qui a tout juste — et c'est très exactement l'erreur que
le § 7 existait pour éviter.

**Ce que l'épisode ne fait pas.** Il ne note pas (aucun barème, aucune pondération : un verdict par
assertion, et le correcteur décide), il n'exécute rien dans un invité, et il n'ajoute **aucun** verbe
au canal — `bin/` n'est pas touché. La seule requête qu'il émet et qui ne soit pas une pure lecture
est `report`, parce qu'un instantané ne vaut que ce que dit sa date ; `--refresh=never` lit le
dernier rapport pris, ce qui est exactement ce que veut dire *corriger une séance déjà terminée*.

### 4.17 Ce que l'épisode 18 a livré (et le verbe qui change la nature du canal)

M2 — « faire faire quelque chose à un invité » — est le seul des quatre manques du § 7.3 que
l'épisode 16 a laissé ouvert, et il l'a laissé ouvert **exprès** : les huit verbes qui le
précèdent observent, celui-ci **commande**. Le § 7.6 le chiffrait comme la voie 2, « même
mécanique, mais générique », et ajoutait : *à trancher explicitement*. L'auteur a tranché.

**Ce qu'il apporte, et que rien d'autre ne pouvait apporter.** Un rapport décrit un **état** —
les adresses, les routes, le pare-feu — et l'épisode 16 en a fait un instantané à la demande.
Mais « m1 joint h3 » n'est pas un état de m1 : c'est une propriété du **chemin**, qui dépend de
h3, du switch, des câbles, des règles des deux côtés, et qui change sans que rien ne bouge dans
le rapport de personne. Le banc le mesure de la façon la plus directe qui soit : on éteint h3, et
le rapport de m1 est **le même** alors que la réponse a changé.

**La mécanique est celle de l'épisode 16, à une addition près.** Le hostfs reste le seul chemin de
retour (D1), donc le protocole est le même — l'hôte efface le `.done`, pose la requête, l'invité
consomme, produit, publie par un `mv`, écrit le `.done`. L'addition est un **identifiant** : un
rapport est idempotent, donc servir deux fois une vieille requête ne coûtait qu'un rapport, alors
qu'exécuter deux fois une commande est un **effet**. L'hôte nomme chaque requête, l'invité répète
le nom, et une réponse qui en porte un autre n'est pas une réponse.

**Un seul veilleur, d'où un renommage.** `marionnet-report-watch.sh` est devenu
`bin/scripts/marionnet-watch.sh` et sert les deux requêtes dans **une** boucle. Le § 6 consignait
déjà le prix du sondage — un réveil par seconde et par invité, faute de toute notification dans un
hostfs — et un second veilleur l'aurait doublé pour rien. Le renommage coûte quatre points
d'accroche mécaniques (`INCLUDE_AS_STRING`, `preprocessor_deps` de `bin/dune`,
`make_hostfs_content`, l'unité systemd écrite par l'épilogue) et rend au fichier un nom qui ne
ment pas.

**Le 7ᵉ journal, et pourquoi il n'est pas facultatif.** Ce que le canal exécute est écrit dans
`exec.log` : la commande, sa date, son statut — jamais sa sortie, qui est servie dans la réponse
(une chose est servie à un seul endroit). Sa raison d'être est la **notation** : sans lui, ce que
le correcteur a injecté serait indiscernable de ce que l'étudiant a fait, et pire, un `exec` qui
passerait par un shell interactif polluerait `commands`, le fichier même que l'on lit comme le
travail de l'étudiant. Deux écrivains, deux fichiers : la règle appliquée depuis l'épisode 8
(console et terminal ne sont jamais fusionnés, pour la même raison).

**Deux pièges mesurés, tous deux dans le transport de la ligne de commande.**

1. **Les options sont reconnues où qu'elles soient** dans une requête — `rc-set m1 <contenu>
   --field=zebra` place la sienne en dernier —, donc `exec m1 ls --all` aurait exécuté `ls` et
   **avalé** `--all` en silence. Deux corrections, indissociables : `parse_request` reconnaît
   désormais le séparateur `--` (tout ce qui suit est un argument, comme dans tout outil Unix), et
   `exec` **refuse** une option qu'il ne connaît pas — c'est le refus qui rend le séparateur
   découvrable, un message que personne ne lit étant un message dont personne n'avait besoin.
2. **Le quoting ne survit pas au shell de l'appelant.** Le canal est orienté ligne : les quotes
   qui **arrivent** au serveur sont transmises telles quelles au bash de l'invité, mais celles que
   le shell du client a mangées avant d'appeler `mrnctl` n'arrivent jamais. Mesuré au banc de
   documentation, sur exactement cette paire : `mrnctl exec m1 -- sh -c 'exit 7'` rend **0** (le
   shell appelant a retiré les quotes, l'invité a exécuté `exit`), là où
   `mrnctl exec m1 "sh -c 'exit 7'"` rend **7**. La règle — passer une commande composée comme
   **un seul argument** — est celle des queues libres depuis toujours ; elle est maintenant écrite
   dans le guide, avec la mesure qui la justifie.

**La borne, et pourquoi elle est double.** `--timeout=<s>` borne la commande **dans l'invité**, et
le canal attend un peu plus longtemps (15 s de grâce). Ce n'est pas de la prudence : borner les
deux avec la même valeur ferait expirer l'attente à l'instant même où l'invité tue la commande, si
bien qu'un dépassement n'aurait jamais pu être **rapporté** — le client n'aurait appris que ce
qu'il savait déjà (pas de réponse). Avec la grâce, la réponse dit `timed_out: true`, porte le
statut 124 et la sortie produite avant l'arrêt, et le journal `exec` en garde la ligne.

**Le vérificateur, sans rouvrir sa grammaire.** L'épisode 17 avait écrit `reaches` et l'avait
refusée **par nom**, en cherchant dans `help` le verbe qui la porterait. Ce mécanisme a fonctionné
tel quel : le jour où `exec` est publié, la famille cesse d'être sautée. Ce qui a dû être écrit,
en revanche, c'est son **corps** — l'annonce de la fiche mémoire (« sans rouvrir le fichier »)
était inexacte, et la mesure l'a dit tout de suite : après le test de capacité, `mrn-verify`
rendait un `SKIP` inconditionnel. Le corps résout l'adresse de la cible **par son rapport** (le
seul endroit où une adresse réellement configurée existe, M4), puis joue un `ping` par `exec`. Le
troisième verdict garde tout son sens : une cible éteinte, ou qui ne publie aucune adresse, donne
un `SKIP` qui **nomme** ce qui manque — l'adresse, pas la connectivité. La grammaire s'ouvre au
passage à une **adresse écrite**, pour les cibles qu'un projet ne modélise pas.

**Ce que l'épisode n'ajoute pas.** Aucun pouvoir : qui pilote le canal peut déjà ouvrir un terminal
root sur un invité d'un double-clic. Ce qui change, c'est que le geste devient **scriptable** —
et, par le 7ᵉ journal, **traçable**, ce que le terminal n'est pas. La limite est celle de tout le
chantier et elle est écrite dans le guide : l'échange passe par le hostfs, que l'invité peut
écrire, donc un étudiant déterminé peut forger une réponse comme il peut forger trois des
journaux. Seule la console (D2) lui échappe.

**Mesures.** `_claude-local/bench/exec-bench.sh` : **60 assertions, 0 échec** (30 sans UML).
Bancs existants mis à jour et rejoués : documentation **66/0** (dont l'exemple neuf `07-exec.sh`,
joué tel quel), vérificateur **84/0**, journal **171/0**, complétion **60/0** —
et la complétion n'a **pas** été touchée : le 7ᵉ journal y arrive parce qu'elle demande la liste à
`help`, et le placeholder du nouveau verbe s'appelle `<command-line>` et non `<command>`, ce
dernier désignant déjà un verbe **du canal** dans cette grammaire.

### 4.18 Ce que l'épisode 19 a livré (et la citation qu'il fallait faire vérifier)

L'épisode 15 avait **planifié** celui-ci et dit pourquoi il devait venir en dernier (D6). Ce qu'il
livre n'est ni un verbe ni un journal : c'est la **procédure** qui manquait entre l'outillage et
son usage — comment on va d'un **énoncé** à une **note**.

**Le fichier, et son emplacement.** `doc-src/lab-design-skill.md` (anglais, 614 lignes) vit dans
la documentation **livrée**, pas dans `.claude/` : un enseignant qui installe Marionnet doit
l'avoir, et n'importe quel agent capable de lancer un shell doit pouvoir le lire — la demande
disait « générique, pas forcément Claude Code ». Le wrapper `.claude/skills/marionnet-lab-design/`
existe quand même, mais il ne fait **que renvoyer** au fichier (12 lignes non vides, mesuré par le
banc) : c'est la discipline d'unicité appliquée au skill lui-même.

**La tension qu'il a fallu trancher, et comment.** L'invariant du dépôt interdit de recopier la
grammaire ailleurs que dans `help` — le § 4 du guide utilisateur s'intitule littéralement « The
command list is not in this guide ». Mais un agent à qui l'on ne dit pas **ce qui existe** ne peut
pas concevoir : il inventera un verbe plausible plutôt que de demander. Décision de l'auteur :
**citer, et faire vérifier la citation** — le motif de l'épisode 9, poussé d'un cran. Le skill
nomme les 43 verbes, groupés par **intention** et non par ordre alphabétique, avec un exemple
chacun ; il ne porte **aucune arité, aucune liste d'options**. Et le banc mesure la citation dans
les **deux sens** :

- tout verbe publié par `help` est nommé au § 1 du skill — un verbe neuf **casse le banc**, il ne
  laisse pas la doc vieillir en silence ;
- aucune **ligne de syntaxe** publiée par `help` n'apparaît dans le skill — c'est-à-dire
  précisément ce qui dérive.

La seconde assertion a d'abord rendu un échec, et c'était le **banc** qui avait tort : sept verbes
sans argument (`status`, `quit`, `start-all`…) ont pour syntaxe leur propre nom, si bien que les
nommer était compté pour une copie. Corrigé en excluant les syntaxes égales au verbe — la mesure
porte sur l'arité et les options, pas sur le nom.

**Ce que le skill contient, et pourquoi c'est cet ordre.** Cinq directives d'abord (demander la
grammaire ; le canal ne peut que ce que la GUI peut ; `accepted` ≠ `done` ; `SKIP` ≠ `FAIL` ; une
note repose sur ce que l'**hôte** a écrit) — parce que ce sont elles qui, enfreintes, produisent un
travail qui a l'air juste. Puis la carte des capacités par intention, le cycle de vie et ses
artefacts (`.mrn`, `.mar`, scénario, `.mrv`), le tableau de ce qui est **prouvable et par quoi**,
la **hiérarchie de preuve** en trois niveaux, l'écriture du corrigé, les onze pièges mesurés du
chantier avec leur contre-règle, un TP complet, la procédure de notation d'une session `--exam`, et
une checklist de livraison.

**Le TP d'exemple est joué, pas rédigé.** Deux points l'ont fait bouger, et tous deux par la
mesure :

- il devait porter un **routeur** — c'est ce qu'un vrai TP emploie. Mais la seule image de routeur
  installée date de 2014 et ne démarrait pas (§ 4.7). Un exemple qu'on ne peut pas **jouer** n'est
  qu'un texte : le nœud qui routait était donc une **machine à deux interfaces**, et le skill
  disait en toutes lettres pourquoi. **Caduc depuis l'épisode 20** (§ 4.19) : le routeur démarre,
  le § 7 du skill porte de nouveau un composant `router`, et l'encadré ne parle plus d'une
  substitution mais de ce qui reste vrai — le modèle dit `port0`/`port1` là où l'invité dit
  `eth0`/`eth1` ;
- son scénario écrit `sysctl -w net.ipv4.ip_forward=1` et **non** `echo 1 > /proc/…`. Ce n'est pas
  une élégance : avec la redirection, l'assertion `journal r1 rc_config contains ip_forward`
  **échouerait sur une machine correcte** (§ 7.4, `set -x` ne trace pas les redirections). Le skill
  garde les deux assertions, l'une sous l'autre, et explique laquelle prouve quoi.

**Le discriminant est le corrigé lui-même, joué deux fois.** Sur la maquette conforme, hors mode
examen : **13 PASS, 1 FAIL, 0 SKIP** — et le seul échec est `documents m1 has Terminal of`, c'est-à-dire
exactement l'assertion que le § 7.4 du skill annonce comme réservée à la session d'examen. Puis le
banc applique au skill le **point 5 de sa propre checklist** (« jouer le corrigé contre une maquette
délibérément fausse ; un corrigé qui passe sur tout ne prouve rien ») : on coupe le forwarding **en
marche**, par `exec` (ép. 18), et on rejoue le **même** fichier. Ce qui bascule est l'**état**
(`report … ip_forward`) et l'**expérience** (`reaches m1 m2`) ; ce qui ne bouge pas est la
**trace** (`journal … contains ip_forward`), qui prouve un **appel** et jamais un état. Le § 4.2 du
skill n'est donc pas un raisonnement : c'est une mesure, sur la même machine, au même instant.

**Mesures.** `_claude-local/bench/skill-bench.sh` neuf : **58 assertions, 0 échec** (dont **41 sans
démarrer une seule UML**, jouables par `--static`). Aucun `.ml` touché, aucun `msgid` introduit —
comme les épisodes 9 et 15, celui-ci est documentaire.

### 4.19 Ce que l'épisode 20 a mesuré (et la question qu'il fallait poser à `timeout`)

Cet épisode n'ajoute **aucune fonctionnalité**. Il joue ce que le chantier n'avait jamais pu jouer :
depuis l'épisode 7, tout ce qui est écrit pour les invités est **symétrique dans le code**
(`machine.ml` et `router.ml` appellent le même geste), mais aucune ligne n'avait jamais tourné sur
un **routeur**. L'unique image installée, `router-guignol-18474` (buildroot/busybox, 2014), recevait
par défaut le noyau `3.2.64-ghost`, dont le stub SKAS0 segfault sur un hôte ≥ 5.15 ; le commit
`79c25dd` — « the default kernel is now the most recent installed » — a levé cela, et le § 6 portait
depuis le 2026-08-13 la **liste close** de ce qui restait à rejouer.

**Le défaut trouvé en jouant, et c'est le seul de l'épisode.** Trois scripts déposés dans l'invité
bornaient leurs commandes par `timeout(1)` derrière une garde `type -p timeout` : le veilleur
(`marionnet-watch.sh`, ép. 16 et 18), le producteur de rapport (`marionnet-report.sh`, ép. 7) et le
collecteur (`marionnet-relay.zz-journal.sh`, ép. 2). Or cette image **a** un `timeout` — celui de
busybox 1.22, dont l'interface est l'**ancienne** (`timeout -t SECS PROG`). La forme moderne
`timeout 180 /bin/bash -c …` y cherche donc un programme nommé « 180 », et **tout** en découle :
chaque `exec` rendait `status 127` et `timeout: can't execute '180'`, chaque section du rapport
était vide, chaque section de la collecte aussi. C'est **mot pour mot** la leçon de l'épisode 14 sur
`tee` : `type -p` teste un **moyen**, jamais une **capacité**. Les trois gardes **jouent** désormais,
une fois, la forme qu'elles s'apprêtent à utiliser (`timeout 1 true`), et le repli du veilleur
**nomme sa raison** dans le journal `exec` que le canal sert — un repli muet se serait fait oublier.

**Le discriminant tient en un nombre, mesuré dans les deux sens sur le même invité** (code précédent
restauré par `git stash`, binaire reconstruit, banc rejoué) : le rapport d'un routeur porte **17**
sections « can't execute » avant, **0** après — et, après, l'adresse des interfaces, la table de
routage et `net.ipv4.ip_forward = 1`. Un rapport **présent et vide** est le pire cas pour une
notation : il a l'air d'une réponse.

**Ce que le rejeu a établi, point par point** (la liste du § 6, close le 2026-08-13) :

| # | Ce qui n'avait jamais été joué | Résultat |
|---|---|---|
| 1 | **Mode examen sur un routeur** (ép. 7) | `documents` porte les **quatre** entrées — rapport, historique, console, terminal — et elles survivent au cycle `.mar`. Deux conditions, toutes deux mesurées : le rapport doit être **demandé avant l'extinction** (cette image SysV n'a pas de séquence d'arrêt, § 4.7 — le rapport à la demande de l'ép. 16 écrit **le même fichier**, et l'archivage le trouve), et l'historique suppose un shell qui **a un `HOME`** (cf. ci-dessous) |
| 2 | **Les cinq journaux d'un routeur** (ép. 1-3, 6, 14) | les **sept** répondent : `rc_config` (avec la fin de la configuration, donc rien de perdu), `boot` (branche **sysv**, `dmesg` via klogd), `console`, `terminal` (l'écran de login de l'image, avec ses séquences ANSI), `commands`, `report`, `exec`. `/dev/fd` **existe** au runtime sur cette image : le piège de l'ép. 14 ne s'y produit pas |
| 3 | **`report` et `exec` sur un routeur** (ép. 16, 18) | fonctionnent — **après** le correctif ci-dessus, sans lequel aucun des deux ne rendait quoi que ce soit d'utile |
| 4 | **Le TP d'exemple du skill** (ép. 19) | réécrit avec un vrai composant `router` (`add router r1 --ports=2`, câbles sur `port0`/`port1`, adresses **déclarées** — elles arrivent dans l'invité au démarrage) et **rejoué** : **13 PASS / 1 FAIL / 0 SKIP** sur la maquette conforme, le FAIL étant l'assertion réservée à l'examen ; puis forwarding coupé en marche → **11 PASS / 3 FAIL**, l'état et l'expérience basculent, la trace non |
| 5 | **Les sept configurations Quagga** par `--field=` (chantier `pilotage-par-script`, ép. 12) | posées composant **éteint** (une modification en marche est refusée, et c'est mesuré), puis **relues dans l'invité** : chaque `/etc/quagga/<srv>.conf` porte ce que le canal a écrit, et `zebra`, `ripd`, `ospfd`, `bgpd`, `ripngd`, `isisd` tournent **sur ces fichiers-là** |
| 6 | **Les deux documents livrés devenus faux** | corrigés : `doc-src/exam-mode.md` § 5 (le routeur est mesuré de bout en bout ; sur une image SysV, on demande son rapport avant de l'éteindre) et l'encadré du § 7 du skill (il ne parle plus d'une substitution, mais des deux noms d'une même interface) |

**Deux découvertes de terrain, l'une utile à l'enseignant, l'autre à qui écrit un banc :**

- **le rapport à la demande sauve le mode examen sur les vieilles images.** Le § 6 tenait le rapport
  d'une image SysV pour hors de portée. C'est vrai du **hook d'arrêt**, et faux du résultat : un
  `report <c>` pendant la session écrit `report.md` à l'endroit exact où l'archivage ira le
  chercher. Une commande, et la limite tombe — c'est désormais écrit dans `exam-mode.md` ;
- **l'historique d'un invité dépend d'un `HOME`, pas du fragment.** Sur guignol, `bash_history.text`
  restait vide alors que le fragment de l'ép. 7 était bien déposé **et** accroché à `/root/.bashrc`.
  La raison : le relais tourne avec `HOME=/` (l'init de cette image n'en pose pas), un bash
  interactif **non-login** lit `/etc/bash.bashrc` — absent ici — puis `~/.bashrc`, donc `/.bashrc`,
  qui n'existe pas. Avec `HOME=/root`, l'historique s'écrit. **Rien à corriger dans le dispositif** :
  un étudiant se **logue**, donc son shell est un shell de login, qui lit `/etc/profile` puis
  `/etc/profile.d/` — vérifié sur cette image. C'est le **banc** qui simulait un cas qui n'existe
  pour personne, et c'est lui qui a été corrigé.

**Un défaut consigné, hors périmètre de l'épisode** (§ 6) : `wait --ready` **ment au second
démarrage**. `make_hostfs_content` est appelé dans l'`initializer` de `uml_process`
(`simulation_level.ml:1530`), donc à la **création** du device simulé — lequel survit au `poweroff`.
Ni `boot_parameters` ni le marqueur ne sont réécrits au démarrage suivant, si bien que la comparaison
de fraîcheur de `cmd_wait_ready` compare un marqueur périmé à un `boot_parameters` tout aussi périmé
et répond `ready: true` en 50 ms. Mesuré sur **machine et routeur** : ce n'est pas une propriété du
genre. Même famille que le défaut connu du `rc-set` sur un switch — un état capturé à la création
d'un device qui survit à l'extinction.

**Mesures.** Banc neuf `_claude-local/bench/router-bench.sh` : **60 assertions, 0 échec** (10 sans
UML). `exam-bench.sh` : **81 assertions**, dont les **quatre** entrées `documents` du routeur, et
**1 échec** — l'assertion « le prompt de login » de l'ép. 8, sur la **machine** trixie, qui échoue
depuis le 2026-08-13 de manière systématique ; le run de contrôle **avec le code précédent restauré**
échoue de la même façon, donc cet épisode n'en est pas la cause (consigné au § 6). Bancs existants
rejoués un par un : `skill-bench` 58/0, `doc-bench` 66/0, `verify-bench` 84/0, `exec-bench` 60/0,
`journal-bench` 171/0.

### 4.20 Ce que l'épisode 21 a livré (et l'exemple qui n'est pas une citation)

**Le point dur n'était pas d'écrire, c'était l'invariant.** Le tableau du § 4 promet depuis
l'épisode 0 « un exemple **par commande** ». Or le guide de scripting **refuse** explicitement une
table des commandes (son § 4, « The command list is not in this guide ») et dit pourquoi : une
seconde liste est juste le jour où on l'écrit, fausse ensuite. L'épisode 19 avait déjà tranché un
cas voisin en citant les verbes **sans** leur syntaxe et en faisant vérifier la citation ; ici, un
exemple **est** une syntaxe, donc la même réponse ne suffisait pas.

**Décision (auteur, 2026-08-13) : les exemples ne sont pas des citations, ce sont des gestes
joués.** Le § 4 du guide neuf `doc-src/teacher-guide.md` est une **session** ordonnée — construire,
configurer, démarrer, observer, éteindre — dont chaque ligne est exécutée par le banc contre une
Marionnet vivante. La couverture n'est pas relue, elle est **mesurée par l'exécution** : pendant le
rejeu, une fonction `mrnctl` espionne note le verbe de chaque appel, et cet ensemble est comparé à
celui que `help` publie **dans les deux sens**. Conséquences, et c'est ce qui distingue ce § d'une
table : un verbe ajouté au serveur **casse le banc** tant qu'il n'a pas son exemple, et une option
renommée fait **échouer** l'exemple qui l'emploie — là où une table recopiée se serait tue.

**Ce qui est livré.**

| Livrable | Ce que c'est |
|---|---|
| `doc-src/teacher-guide.md` | le **fil de l'enseignant** : de l'énoncé à la note. Renvoie aux trois documents existants au lieu de les répéter ; porte l'**index** (§ 4) et le § « concevoir et noter avec un agent IA » (§ 6) |
| `doc-src/labs/session-7/` | un **TP réel complet** (C4 du corpus : routage, filtrage, SNAT) : énoncé, `lab.mrn`, scénarios d'invité, corrigé, **deux** clés (session vivante / copie close), `build.sh`, `play.sh`, `grade.sh` |
| `_claude-local/bench/teacher-bench.sh` | le banc : prose sans grammaire recopiée, index joué ligne à ligne, couverture bidirectionnelle + deux discriminants, TP joué tel quel, copie d'examen notée |

**Le § 6 du guide est écrit du côté de l'enseignant, pas de l'agent.** Le skill de l'épisode 19
dit à l'agent *comment faire* ; ici on dit à l'humain **quoi exiger** avant d'y croire : les
compteurs d'un run complet, la clé jouée contre un TP **délibérément faux**, la liste des `SKIP`,
et le `.mar` sauvé-quitté-rejoué. Et ce qu'il ne délègue pas : les ambiguïtés de l'énoncé, le
barème, la sanction.

**Le discriminant de l'épisode est le TP, joué deux fois de suite sur la même session.** Corrigé
installé : **14 PASS / 0 FAIL / 0 SKIP**. Puis, forwarding coupé **en marche** par
`exec r1 -- sysctl -w net.ipv4.ip_forward=0`, la **même** clé rejouée : **12 PASS / 2 FAIL**, et
les deux qui basculent sont exactement l'**état** (`report r1 says ~ ip_forward *= *1`) et
l'**expérience** (`reaches m1 intruder`) — la **trace** (`journal r1 rc_config ok`) passe encore,
parce qu'elle dit vrai : la configuration a bien tourné. C'est la hiérarchie des preuves du § 7.5,
rendue visible en deux lignes de sortie.

**Pièges neufs, tous mesurés.**

1. **Le quoting d'un `rc-set` qui redirige.** `rc-set m1 printf 'x' > /mnt/hostfs/…` fait
   rediriger **le shell de l'appelant** : la queue libre part à l'invité, mais c'est bash qui lit
   la ligne en premier. Il faut quoter la queue entière. Même famille que le quoting d'`exec`
   (ép. 18), et ça se voit à l'œil nu seulement quand on **joue** la ligne.
2. **Les ports ne se nomment pas pareil selon le genre** : une machine a `eth0…`, un **composant
   `router` a `port0…`**, un switch et un hub `port1…` (ils comptent à partir de 1). Le refus le
   dit, mais un exemple faux n'aurait été trouvé que par un lecteur.
3. **`wait --ready` sans marqueur attend pour rien** : le marqueur est écrit **par le scénario**,
   jamais par le relais (ép. 16). Un `rc-set` qui ne l'écrit pas fait expirer l'attente à 300 s —
   d'où l'ordre du § 4, où le scénario minimal vient **avant** le premier démarrage.
4. **Les titres des documents archivés sont traduits** : une session française classe le rapport
   sous « Rapport sur m1 » quand la console reste « Console of m1 ». Un corrigé qui cherche
   `Report on` ne note **rien** chez un collègue. Rien du canal n'est localisé ; le treeview, si.
5. **Le rapport d'arrêt n'est pas garanti.** Trois machines éteintes peu après leur boot : **une
   seule** avait écrit son `report.md` (les trois avaient console et terminal). Le remède est
   celui de l'épisode 20, et il coûte une commande : **demander `report <c>` avant l'extinction**.
   Consigné au § 6.
6. **`quit` rend la main sans garantir que le processus est mort** — et supposer le contraire
   laisse des sessions Marionnet s'accumuler : trois tournaient en parallèle, chacune avec ses
   UML, ses taps et la **même** adresse d'extrémité `172.23.0.254`, ce qui faisait échouer le boot
   d'un invité de la session suivante (`wait --ready` expire à 300 s) alors que le même TP joué
   seul aboutit. Piège **de banc** — le dépôt le savait déjà (`bench_cleanup`) — réparé par un
   `end_session` qui **attend** la mort, puis TERM/KILL **par PID exact** (§ 6).
7. Deux pièges d'écriture de banc, payés tous les deux : un **programme awk cité par des
   apostrophes** ne peut contenir **aucune apostrophe**, pas même dans un commentaire français —
   sinon le shell referme la chaîne et le programme est cassé **en silence** (zéro verbe extrait,
   et un flux de contrôle déviant) ; et `pgrep -c -f <motif>` **se compte lui-même** (le `[l]inux`
   habituel), en **imprimant** `0` tout en **rendant** 1, de sorte qu'un `|| echo 0` produit
   « 0\n0 » et casse le `(( ))` qui suit.

**Mesures.** Banc neuf `_claude-local/bench/teacher-bench.sh`. Sans UML (`E2E=0`) : **13
assertions, 0 échec** — la prose ne recopie aucune ligne de syntaxe de `help`, les trois renvois
et les neuf fichiers du TP cités existent, `mrn-check` valide le `.mrn` (14 requêtes) et
`mrn-verify --check-only` les deux clés (14 et 10 assertions), la couverture est complète
(**43 verbes publiés, 43 exemples**) et les deux discriminants mordent. Avec UML : les **57 lignes** du § 4 sont jouées dans l'ordre et
**rendent toutes 0** — donc `wait --ready`, `report`, `switch-info`, `exec` et les trois
`history-*` compris — et les verbes **joués** sont exactement ceux que la lecture statique
annonçait. Le TP : **14 PASS / 0 FAIL / 0 SKIP**, puis **12 / 2** après coupure du forwarding. La
copie d'examen : **neuf** documents archivés (trois par machine — le `report` demandé avant
l'extinction fait exactement ce que le § 5.5 du guide promet), **aucun** historique (personne ne
s'est logué : le fragment `/etc/profile.d` n'est lu que par un shell de login, ép. 20), et la
notation d'une copie close rend **10 PASS / 0 FAIL / 0 SKIP** sans redémarrer un seul invité.
Total du banc complet : **37 assertions, 0 échec**. Aucun `.ml` touché, `dune build` vert. Bancs
existants rejoués — ceux qui **lisent** les documents modifiés : `skill-bench` **60/0**,
`doc-bench` **66/0**.

### 4.21 Ce que l'épisode 22 a livré (et le bouton d'à côté)

**Le constat.** Tout ce que ce chantier archive — rapport, historique des commandes, console,
terminal, dans le treeview `documents`, donc dans le `.mar` remis à l'enseignant — est accroché à
**un seul** chemin du modèle : `gracefully_shutdown_right_now` (`machine.ml`, `router.ml`). Ce
n'est pas un oubli d'implémentation, c'est une conséquence : le rapport de fin de session est
écrit **par l'invité**, à l'arrêt. Mais il en découle que **tout autre chemin d'extinction jette
la copie**, et qu'aucun d'eux ne le disait :

| Geste | Ce qu'il appelle | Archivage |
|---|---|---|
| « Tout arrêter » ; `stop`, `shutdown-all` | `gracefully_shutdown_right_now` | oui |
| **« Tout débrancher »** (`Power-off all`) | `poweroff_everything` → `poweroff_right_now` | **non** |
| **`poweroff <c>` / `poweroff-all`** | idem, par composant | **non** |
| **Quitter → « ne pas sauver »** | `poweroff_everything`, puis on quitte sans rien écrire | **non** |
| **`quit` du canal** | `destroy_process_before_quitting`, et rien n'est sauvé | **non** |
| `close --no-save`, `new`, `open` | arrêt **gracieux**, mais l'archive n'atteint pas le `.mar` | à moitié |
| `del` / « Supprimer » | `destroy_right_now`, qui débranche d'abord | **non** |

Le plus accessible d'entre eux est **voisin du bon** dans la barre du bas : « Tout débrancher »
touche « Tout arrêter ». Deux clics suffisaient à effacer une copie d'examen, et rien dans
l'interface ne le signalait. Jusqu'ici, `--exam` ne **verrouillait rien** : ses seuls effets
étaient l'icône, le titre, `exam=1` passé au noyau, l'archivage lui-même et la fenêtre source en
lecture seule (ép. 12).

**Livré : le mode examen refuse ce qui détruit sans archiver.**

- **Débrancher n'existe plus en examen.** `can_poweroff` porte le facteur
  (`Initialization.are_we_allowed_to_poweroff`), donc le canal refuse `poweroff` et `can` ne le
  publie plus, **sans que le serveur ait à connaître la règle** ; le bouton de la barre du bas est
  insensible avec un infobulle qui dit pourquoi ; et `State#poweroff_everything` refuse en
  ceinture, pour qu'un futur appelant ne rouvre pas le trou en silence. Rien n'est perdu : les
  chemins internes qui ont réellement besoin d'une coupure brutale — `destroy_right_now`, le repli
  d'un arrêt gracieux avorté — appellent `poweroff_right_now` **sans** consulter le prédicat.
- **Quitter sauvegarde.** En examen, la question « voulez-vous sauver avant de quitter ? » n'est
  **plus posée** : tant qu'un projet est ouvert, quitter veut dire arrêt gracieux **puis**
  sauvegarde. Ce n'est pas une boîte de dialogue qu'un étudiant doit réussir sous la pression.
- **Supprimer : le critère est la trace, pas le mode.** Un composant **jamais démarré** reste
  supprimable — il n'a rien produit, et un étudiant qui construit sa maquette doit pouvoir défaire
  une erreur. Dès qu'il a tourné, sa suppression est refusée, et l'option **`--exam-allow-delete`**
  la rend à qui lance la session. Le prédicat `has_left_traces` a **deux** sources parce
  qu'aucune ne suffit : le treeview des états (**persisté** dans le `.mar`, donc encore vrai
  après réouverture) et un drapeau mémoire `ever_started` (qui couvre la session courante et
  surtout les genres **sans** états de disque — un switch qui a tourné a écrit son
  `<nom>-rc_config.log`).
- **Le canal dit la même chose que la GUI, et le dit autrement.** `del` et `poweroff` sont refusés
  par le modèle ; les refus sont pris en charge par un code neuf, **`forbidden_in_exam_mode`**,
  et non par `forbidden_transition` : dire « m1 ne peut pas être supprimée dans l'état off »
  enverrait un script chercher un état qui n'existe pas. `--no-save` est refusé plutôt que
  **silencieusement** transformé en sauvegarde, et `quit` est refusé tant qu'un composant tourne
  ou que le projet a des changements non écrits — jamais dans l'absolu, parce qu'une session
  d'examen pilotée doit pouvoir se terminer elle-même (`close --save` puis `quit`).
- **La découvrabilité suit l'invariant.** La grammaire de `help` n'a **pas** bougé : la restriction
  est une **capacité**, pas un mot. `can` cesse de publier `poweroff`/`del`, et `status` publie
  désormais `exam` — parce que `can` parle des composants, alors que `poweroff-all`, `new`,
  `open`, `close` et `quit` sont des gestes de **session**, dont rien ne disait le sort.

**Le seuil mesuré, pas supposé.** `number_of_states_with_name > 1` et non `> 0` : `add_device`
insère une ligne racine vierge dès l'ajout du composant. Mesuré dans les deux sens — 1 ligne sur
une machine fraîche, 2 après un cycle réel — et attention à la lecture : le `count` de la réponse
`history` est le nombre de **racines**, l'état produit par une exécution étant un **enfant**.

**Le discriminant** est la même machine, dans deux processus : après un boot réel, un `stop` et un
`save`, le projet est rouvert dans une Marionnet **neuve** lancée en `--exam` — donc `ever_started`
est faux — et `del m1` est **refusé** quand même, puis **accepté** en relançant avec
`--exam-allow-delete`. C'est le `.mar` qui parle, pas la mémoire.

**Mesures.** Deux bancs jetables. Le premier, sur trois sessions (sans `--exam`, `--exam`,
`--exam --exam-allow-delete`) et la même maquette : **43 assertions, 0 échec**, dont le couple qui
porte tout — le **même** switch, dans le **même** état `on`, publie `poweroff` hors examen et ne le
publie plus en examen. Le second, avec boot UML : **19 assertions, 0 échec**. GUI vérifiée à
l'écran : bouton « Tout débrancher » grisé, case du menu Options visible et **cochée-grisée**,
sous-menu « Supprimer » du switch **vide** après son cycle. `dune build` vert.

**Piège de banc (deux runs perdus)** : le serveur de contrôle refuse de servir une socket dont le
répertoire parent est écrivable par d'autres (`3220ef2`) — et il le refuse **sans un mot sur la
sortie standard**. Un `mkdir` sous umask 002 suffit à ne jamais voir la socket apparaître.

### 4.22 Ce que l'épisode 23 a livré (et la sauvegarde qui arrivait trop tôt)

**Le constat de l'auteur, et ce qu'il a fallu vérifier avant d'y répondre.** L'épisode 22 avait
traité **Quitter** ; restaient **Fermer**, **Nouveau** et **Ouvrir**, qui posent tous les trois la
question « voulez-vous enregistrer le projet en cours ? » et acceptent « Non ». C'est la question
dont la mauvaise réponse coûte le plus cher : les documents archivés à l'extinction ne vivent dans
le `.mar` **que** si le projet est sauvé. Un étudiant qui clique « Non » par réflexe perd sa copie
entière.

Deux points de l'énoncé ont été **mesurés plutôt que crus** :

- le `(x)` de la fenêtre : il appelle la **même** entrée que Projet→Quitter
  (`gui_window_MARIONNET.ml`, événement `delete`), il était donc déjà couvert par l'épisode 22 —
  vérifié, aucune boîte n'apparaît et l'application s'en va toute seule ;
- l'hypothèse « le drapeau `project_already_saved` ment après un archivage » (ce qui aurait rendu
  Quitter silencieux même hors examen) : **fausse**. Mesuré — trois documents archivés,
  `saved` passe à `false` juste après. La garde « déjà sauvé donc rien à demander » est donc
  légitime et elle est conservée.

**Le vrai défaut était ailleurs, et il rendait la sauvegarde forcée inopérante.** `shutdown_everything`
ne fait qu'**ordonnancer** ses tâches sur le task runner et rend la main aussitôt, alors que
l'archivage est le **dernier** geste de chaque arrêt gracieux. Les quatre chemins écrivaient donc
le `.mar` **pendant** que les invités s'éteignaient : une course, gagnée par l'invité seulement
s'il allait assez vite. Pire pour Quitter, dont la réaction tournait dans le **thread GTK** :
`destroy_process_before_quitting` — une coupure brutale — suivait immédiatement.

**Livré**, entièrement dans `bin/gui/gui_menubar_MARIONNET.ml` :

- `Common_dialogs.ask_to_save_current_project`, **une** fonction pour les quatre gestes : pas de
  projet actif → rien ; **mode examen → « oui », sans poser la question** ; sinon la question,
  **augmentée d'un avertissement** quand quelque chose a tourné dans la session. L'avertissement
  se décide avec `has_left_traces`, le prédicat que l'épisode 22 avait déjà publié sur le modèle —
  aucun code neuf pour le savoir ;
- `Common_dialogs.shutdown_then_save`, qui met les trois temps **dans l'ordre** : arrêter,
  **attendre le task runner**, puis sauver. L'attente ne peut pas avoir lieu dans le thread GTK
  (l'archivage y passe par `GMain_actor.apply_extract` depuis l'épisode 12 : le bloquer serait un
  interblocage), d'où le changement le plus structurant de l'épisode — **la réaction de Quitter
  tourne désormais dans un thread**, comme les trois autres depuis toujours ;
- hors examen, la branche « quitter sans sauver » garde son `poweroff_everything` : rien ne sera
  écrit, faire attendre un arrêt gracieux ferait patienter pour rien.

**Le discriminant** ne pouvait pas venir du canal — ces gestes sont des **clics**. Le banc pilote
donc la GUI (`xdotool`, menu Projet) puis **rouvre le `.mar` dans un processus neuf** et compte ce
qu'il contient : Quitter avec une machine encore allumée laisse un fichier portant **Rapport sur
m1**, **Console of m1** et **Terminal of m1** — la course est fermée.

**Trois pièges de mesure, tous payés** : (a) `xdotool key ctrl+q` envoie la touche à **ce qui a le
focus**, ce qui n'est ni fidèle au geste d'un étudiant ni sans danger — les gestes se jouent en
**cliquant dans le menu** ; (b) un banc sous `set -e` **meurt en silence** quand une fenêtre
disparaît sous xdotool — précisément parce que le geste testé la ferme — et ne rapporte alors
**rien du tout** ; (c) les titres des fenêtres de dialogue sont **traduits** : un motif anglais
n'en trouve aucune et transforme « aucune boîte n'est apparue » en affirmation creuse. Enfin, un
premier run a compté deux documents au lieu de trois : ce n'était pas la course mais le défaut
**déjà consigné au § 6** — une machine arrêtée trop tôt après son démarrage n'écrit pas son
rapport.

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
  répond au ctrl-alt-del par `/sbin/halt` (§ 4.7). **Nuance depuis l'épisode 16** : le rapport
  *à la demande*, lui, ne dépend d'aucune séquence d'arrêt — sur ces images il est donc le seul
  des deux à répondre, et il suffit à un correcteur qui prend son instantané avant d'éteindre.
  **Mesuré à l'épisode 20, et la nuance vaut mieux que ça** : ce rapport-là est écrit dans le
  **même fichier** que celui du hook, donc l'archivage du mode examen le trouve et le classe sous
  « Rapport sur … » comme n'importe quel autre. Sur une image sans séquence d'arrêt, le mode examen
  est complet **au prix d'une commande** (`report <c>` avant l'extinction) — c'est dit dans
  `doc-src/exam-mode.md` § 5. Le remède serait d'envelopper `/sbin/halt`
  dans le COW — le motif que ces images utilisent déjà pour `/sbin/shutdown` — mais toucher au
  binaire d'arrêt d'un invité pour un journal n'a pas paru un bon marché ; à rouvrir seulement si
  un TP doit être noté sur une vieille image.
- ~~Le **bout en bout du routeur** attend une image de routeur qui boote (§ 4.7).~~ **JOUÉ ET
  SOLDÉ à l'épisode 20** (§ 4.19), une fois `79c25dd` réparé le choix du noyau par défaut. Les six
  points de la liste close du 2026-08-13 — mode examen sur routeur, ses journaux, `report`/`exec`,
  le TP d'exemple du skill, les sept configurations Quagga vérifiées **dans** l'invité, et les deux
  documents livrés devenus faux — ont tous été rejoués ou corrigés ; le tableau du § 4.19 dit ce
  que chacun a rendu. Ce qui reste de cette entrée n'est plus une attente mais **deux propriétés de
  l'image de 2014**, à retirer le jour où elle sera rénovée : son `timeout` est celui de busybox
  (ancienne interface `-t SECS`, d'où le correctif de l'épisode 20), et elle n'a **pas** de
  séquence d'arrêt, donc son rapport se **demande** avant l'extinction.

- **`wait --ready` ment au second démarrage** (mesuré à l'épisode 20, sur **machine et routeur** —
  ce n'est pas une propriété du genre). `make_hostfs_content` est appelé dans l'`initializer` de
  `uml_process` (`simulation_level.ml:1530`), donc à la **création** du device simulé, lequel
  **survit au `poweroff`** : au démarrage suivant, ni `boot_parameters` ni le marqueur ne sont
  réécrits. La garde de fraîcheur de `cmd_wait_ready` compare alors deux fichiers également périmés
  et répond `ready: true` en 50 ms, sur le marqueur du boot **précédent** — un `exec` qui suit se
  heurte à un veilleur qui n'est pas encore là. Même famille que le `rc-set` d'un switch ci-dessous :
  un état capturé à la création d'un device qui survit à l'extinction. Deux remèdes possibles,
  tous deux dans `simulation_level.ml` : rejouer `make_hostfs_content` au `spawn` (c'est ce que son
  nom laisse attendre), ou effacer le marqueur au démarrage. **Non corrigé** : le chemin de
  démarrage est commun à tous les composants, et cela se tranche avec l'automate d'état en tête
  (chantier clos `marionnet-automate-composants`). En attendant, un banc qui redémarre un invité
  **ne demande pas `--ready`** : il attend que l'invité **réponde** (`exec <c> -- true`).

- **Le prompt de login n'apparaît plus dans le journal `terminal` d'une trixie** (constaté le
  2026-08-13, systématique sur trois passages ; l'assertion correspondante d'`exam-bench.sh` passait
  encore le 2026-08-12, deux fois). Ce n'est **pas** l'épisode 20 : le run de contrôle, avec ses
  trois scripts restaurés par `git stash` et le binaire reconstruit, échoue exactement pareil. Les
  lignes de commande noyau des deux runs sont **identiques**, et les deux `getty` sont démarrés dans
  les deux cas ; ce qui manque est le prompt lui-même, sur toute la durée de vie de la machine. Reste
  à instruire — la piste la plus simple étant une course entre le `getty` de `tty0` et l'extinction
  demandée par l'exemple, sur un hôte plus chargé.

- **Le rapport d'arrêt n'est pas garanti** (mesuré à l'épisode 21, sur trois machines
  `debian-trixie` d'une session `--exam`) : les trois ont archivé leur console et leur terminal,
  **une seule** avait écrit son `report.md`. Les trois avaient pourtant atteint la fin de leur
  relais — les journaux `rc_config` se terminent à l'identique. L'hypothèse la plus simple est
  celle que l'épisode 16 a déjà mesurée pour le veilleur : une unité systemd **démarrée depuis le
  relais** n'a son job exécuté qu'**à la fin du boot**, bien après le marqueur de `wait --ready` ;
  une extinction demandée quelques secondes après ce marqueur la manque donc. **Non instruit** :
  il faudrait mesurer le délai réel entre le marqueur et l'activation du hook, sur plusieurs
  images. En attendant, le remède est celui de l'épisode 20 et il coûte une commande —
  **demander `report <c>` avant l'extinction**, ce que `doc-src/teacher-guide.md` § 5.5 conseille
  et que le banc de l'épisode 21 joue.
- **Un boot d'invité qui n'aboutit pas quand plusieurs sessions Marionnet tournent en parallèle**
  (épisode 21) : `wait m1 --ready` expire à 300 s, le hostfs porte bien les fichiers déposés par
  l'hôte (`boot_parameters`, le relais, le `rcfile`) mais **aucun** fichier écrit par l'invité —
  ni `rc_config.log`, ni `boot.log` : le boot n'a jamais atteint le relais. Le même TP joué
  **seul** aboutit toujours (3 fois sur 3, dont un rejeu dans les conditions du banc). La cause a
  fini par se voir avec un simple `ps` : **trois** processus `marionnet.exe` tournaient ensemble,
  ceux de deux runs précédents compris, chacun avec ses UML, ses taps `mtap<pid>-*` et **la même**
  adresse hôte `172.23.0.254`. Ce n'était donc pas Marionnet : c'était le **banc** de cet épisode,
  qui remettait `MARIONNET_PID=""` après un `quit` **en supposant** que le processus était mort.
  Fait rappelé au passage, et déjà connu du dépôt (`bench_cleanup` le gère depuis l'épisode 6 de
  `pilotage-par-script`) : **`quit` rend la main sans garantir que le processus est parti**. Le
  banc a désormais un `end_session` qui attend la mort, puis TERM/KILL **par PID exact** — et le
  run suivant l'a **journalisé** noir sur blanc (« le processus 765852 a survécu à `quit` — TERM
  puis KILL ») **avant** de jouer le TP du premier coup, 37 assertions et 0 échec. Ce qui reste
  ouvert, et vaut d'être su : deux sessions Marionnet **simultanées** partagent l'adresse
  d'extrémité de leurs taps ; rien n'interdit de les lancer, et personne ne le signale.
- ~~**Les titres des documents archivés sont traduits, et pas tous** : une session française classe
  « **Rapport sur** m1 » à côté de « **Console of** m1 » et « **Terminal of** m1 ». L'incohérence
  elle-même est un défaut : les `msgid` `Console of `/`Terminal of ` ont pourtant été traduits à
  l'épisode 13.~~ **Instruit à la clôture (épisode 24) : ce n'était pas un défaut du chantier, mais
  un artefact de mesure**, et il se mesure en trois gestes. Les **quatre** titres passent par `s_`
  (`treeview_documents.ml:423,649,661,681`) ; `bin/po/fr.po` **et** le catalogue installé du switch
  courant (`$(opam var prefix)/share/marionnet/locale/fr/LC_MESSAGES/marionnet.mo`) traduisent les
  **quatre** ; mais `/usr/share/locale/fr/LC_MESSAGES/marionnet.mo` — le Marionnet **installé sur
  la machine**, daté du **8 juillet 2023** — contient `Report on ` (msgid ancien) et **ni**
  `Console of ` **ni** `Terminal of ` (msgid nés de ce chantier). C'est exactement le mélange
  observé, et sa cause est déjà consignée hors chantier : `docs/TODO.md` § « i18n — en arbre de
  développement, Marionnet lit le catalogue d'un AUTRE Marionnet ». Ce qui **reste vrai** et n'est
  pas un défaut : un corrigé qui cherche un libellé anglais (`documents r1 has ~ Report on`) ne note
  **rien** sur une session française — d'où l'alternative écrite dans
  `doc-src/labs/session-7/key-recorded.mrv`, qui garde sa raison d'être.
- **La page rendue vit deux minutes** (épisode 11 : elle est servie, pas écrite). Corollaire :
  recharger l'onglet du navigateur après ce délai donne une erreur — il faut redemander le
  document. Un compromis assumé : rien ne traîne nulle part, mais rien ne se garde non plus.
- **Les trois chaînes non traduites qui restent** dans les douze catalogues (mesuré à l'épisode 13 :
  382 traduites, 3 non traduites, 0 *fuzzy*) sont les longs textes d'aide de `world_bridge` —
  environ 250 mots, introduits par `modernisation-world-bridge`, à traduire par ce chantier-là.
  Toutes les chaînes de **celui-ci** sont traduites dans les douze langues depuis l'épisode 13.
- ~~Constaté à l'épisode 7 : sur une `debian-wheezy`, `rc_config.log` ne porte que son en-tête.~~
  **Instruit et corrigé à l'épisode 14** (§ 4.14) : `/dev/fd` manque au *runtime* sur cette image,
  donc la substitution de processus du `tee` ne s'ouvre pas et l'`exec` échoue en entier, en
  silence. Le prologue répare `/dev/fd` et **mesure** la substitution au lieu de la supposer.

- ~~**M2 — exécuter dans un invité** (voie 2 du § 7.6, `exec <c> <cmd>`) : laissé ouvert par
  l'épisode 16, **délibérément**.~~ **Tranché et livré à l'épisode 18** (§ 4.17) : le verbe existe,
  le canal a cessé d'observer pour commander l'intérieur des invités, et la décision a été prise
  pour elle-même. Ce qui reste de la précaution de l'épisode 16 est mesuré à l'envers par le banc :
  le verbe qui exécute est `exec` **et lui seul** (ni `run`, ni `shell`, ni `ssh` n'ont été ajoutés
  en passant).
- **Un `rc-set` sur un switch n'est pris en compte qu'au premier démarrage** (mesuré à
  l'épisode 17, en fabriquant son banc). Le contenu du rc est capturé à la **création du device
  simulé** (`switch.ml:464-467`, `make_simulated_device`), et ce device **survit à un `poweroff`** :
  un `rc-set` ultérieur est accepté (`changed: true`), `rc-get` rend bien le nouveau contenu, et
  le démarrage suivant rejoue **l'ancien** — sans que rien ne le signale. Pour une machine le
  problème n'existe pas : son rc est un fichier du hostfs, relu à chaque boot. Deux remèdes
  possibles (passer une *fonction* plutôt qu'une valeur au constructeur du device, ou détruire le
  device simulé quand le rc change), tous deux dans `switch.ml` ; à trancher avec l'automate
  d'état en tête (chantier clos `marionnet-automate-composants`). En attendant, tout banc ou TP
  qui veut deux rc différents utilise **deux switchs**.
- Le **veilleur** interroge ses fichiers-drapeaux toutes les secondes (épisode 16). C'est le prix
  d'un hostfs qui n'offre aucune notification : négligeable sur un UML, mais c'est bien un réveil
  par seconde et par invité, et non zéro. Un `inotify` côté invité supposerait qu'il soit
  disponible dans toutes les images, ce que rien ne garantit. C'est **ce coût-là** qui a décidé
  l'épisode 18 à faire servir `exec` par la **même** boucle plutôt que par un second veilleur —
  d'où le renommage en `marionnet-watch.sh` (§ 4.17).
- Le **quoting d'une commande passée à `exec`** ne survit pas au shell de l'appelant : une
  commande composée doit être passée comme **un seul argument** (§ 4.17, mesuré). Rien à corriger
  dans le canal — il est orienté ligne par construction, comme les queues libres de `rc-set` — mais
  c'est la première chose qui surprendra celui qui écrit un corrigé.

- **Le verrou de suppression de l'épisode 22 ne survit pas à une réouverture pour les genres sans
  état de disque** (switch, hub, cloud, passerelles) : `has_left_traces` s'appuie alors sur le seul
  drapeau de session, faux dans un processus neuf. **Inoffensif, et c'est pourquoi ce n'est pas
  corrigé** : ce qu'un switch écrit (`<nom>-rc_config.log`) vit dans le répertoire de travail du
  projet, lequel est **reconstruit** à l'ouverture du `.mar` — après réouverture, il n'y a plus de
  trace à protéger. Le jour où un journal de switch serait archivé dans `documents`, il faudra
  donner à ces genres une source persistée (ou marquer le composant dans le forest).
- ~~**Les infobulles et le témoin du menu Options de l'épisode 22 ne sont pas encore traduits** :
  deux `msgid` neufs, à passer dans les douze catalogues comme à l'épisode 13.~~ **Fait** par
  `5161c49` (384 traduites / 3 non traduites / 0 *fuzzy* dans les douze catalogues ; les trois
  restantes sont celles de `world_bridge`, ci-dessus).
- **Le mode examen n'empêche toujours pas de fermer la fenêtre par le gestionnaire de fenêtres**
  autrement que par le chemin « Quitter » : c'est le même code (l'événement `delete` appelle la
  même entrée de menu), donc la sauvegarde forcée s'applique — mais un `kill` du processus, lui,
  reste hors de portée par construction. Le remède n'est pas dans Marionnet : c'est la copie
  rendue qui fait foi, et le rapport à la demande (épisode 16) permet de ne pas tout miser sur
  l'extinction.

## 7. Vers le vérificateur : ce qu'un TP demande de prouver (épisode 15)

> **État après l'épisode 19** : ce § a rempli son office — il a spécifié l'épisode 16 (le rapport
> à la demande), l'épisode 17 (le vérificateur), l'épisode 18 (l'exécution dans l'invité) et
> l'épisode 19 (le skill, § 4.18), qui reprend son tableau des preuves, ses manques comblés et ses
> pièges. Les quatre manques M1→M4 sont **tous comblés**. Il reste ici comme **archive de mesure** :
> ne pas le réécrire, le citer.

**D6** dit que le vérificateur à l'exécution et le skill de conception de TP sont des épisodes
*optionnels de fin*, et il dit *pourquoi* : « on ne conçoit pas une couche de verdict avant qu'un
journal ait tourné une seule fois ». Cet épisode est la sonde qui manquait entre les deux. Il ne
livre aucune fonctionnalité : il prend des TP **réels**, écrit ce qu'un corrigé doit pouvoir
**affirmer**, et **mesure** — verbe par verbe, sur une session vivante — ce que le canal sait déjà
prouver et ce qu'il ne sait pas dire. Son résultat utile est la liste des **manques**.

Renumérotation : **15** = cet épisode, **16** = le vérificateur, **17** = le skill.

### 7.1 Le corpus

| # | TP | Origine | Ce qu'il sollicite |
|---|---|---|---|
| C1 | VLAN sur un switch | synthétique | `switch-info` (`vlans`, `macs`), journal du rc de switch (ép. 4) |
| C2 | Routage entre deux LAN | synthétique | table de routage et `ip_forward` **dans** l'invité |
| C3 | Adressage / sous-réseaux | synthétique | adresses réelles, cache ARP, `ping` |
| C4 | Routage + filtrage + SNAT/DNAT | séance 7 de l'auteur (`tp-marionnet-7.tex`, `projet-marionnet-seance-7.mar`) | `iptables` filter **et** nat, services HTTP/SSH, `tcpdump` |
| C5 | IPv6 : autoconf, routage, filtrage | séance 10b de l'auteur (`tp-marionnet-10b.tex`, `my_firewall.sh`) | `radvd`, `ip -6`, `ip6tables`, `ssh` |

C4 et C5 sont ceux qui comptent : de vrais énoncés, avec un corrigé que l'auteur a écrit —
`my_firewall.sh` **est** le corrigé du pare-feu, et le banc le **lit** au lieu de le réécrire. La
maquette mesurée est réduite à ce qui produit les faits à prouver : `m1 — h1 — r1(3 ports) — h3 —
intrus`, images `debian-trixie-47362` (dont le userland porte `iptables`, `ip6tables`, `radvd`,
`nginx`, `sshd`, `tcpdump` — vérifié par `debugfs`, sans monter les images).

### 7.2 Ce que le canal prouve déjà

| Affirmation d'un corrigé | Source | Verdict |
|---|---|---|
| « la topologie est celle de l'énoncé » | `ls`, `get`, treeview des câbles | **prouvable** |
| « le routeur a trois interfaces » | `get r1` → `.fields.port_no` | **prouvable** |
| « les VLAN 5 et 6 existent, le port 3 est dans le 6 » | `switch-info sw1 vlans` | **prouvable** |
| « la configuration du switch s'est exécutée sans erreur » | `log sw1`, absence de `!! FAILED` | **prouvable** |
| « aucune commande du corrigé n'a échoué dans l'invité » | `log r1`, absence de `!! FAILED` | **prouvable** |
| « la règle de SNAT a été posée » | `log r1` (trace `set -x`) | **indirecte** (au boot seulement) |
| « m1 a l'adresse 192.168.1.1 » | treeview `ifconfig` | **indirecte** : le treeview porte le **déclaré** |
| « `ip_forward` vaut 1 » | — | **non observable** en marche |
| « la règle `MASQUERADE` est active maintenant » | — | **non observable** en marche |
| « m1 joint intrus » | — | **non observable** (rien n'exécute dans un invité) |
| « `radvd` tourne sur r1 » | — | **non observable** |
| « l'adresse IPv6 de m1 est … » | — | **non observable** : fabriquée dans l'invité |

### 7.3 Les manques

> **État après l'épisode 16** (§ 4.15) : **M1, M3 et M4 sont comblés** par le verbe `report` et le
> sixième journal du même nom — la voie 1 du § 7.6, la moins intrusive. **M2 reste ouvert**, et
> délibérément : il exige que le canal exécute dans l'invité, ce qui change sa nature. Le texte
> ci-dessous est laissé tel qu'il a été **mesuré** à l'épisode 15 ; ce qui a changé est dit à
> chaque manque.

- **M1 — l'état d'un invité à l'instant *t*.** Les cinq journaux sont des **traces** (ce qui s'est
  dit), `switch-info` est le seul **état** — et c'est celui d'un switch. Mesure : `switch-info r1`
  refuse, en le disant (« a machine: switch-info applies to a switch »).
  **Comblé (ép. 16)** : `report <machine|routeur>` demande à l'invité de se décrire, et
  `log <c> report` sert ce qu'il a écrit.
- **M2 — faire faire quelque chose à un invité.** Aucun des 41 verbes publiés n'exécute, ne lit ni
  n'interroge quoi que ce soit dans une machine. Donc aucun `ping` à la demande, donc aucune
  affirmation de **connectivité** — le cœur de C2, C3 et de la partie « Test » de C4.
  **Comblé (ép. 18)**, après avoir été laissé ouvert par l'ép. 16 et tranché pour lui-même :
  `exec <composant> <ligne de commande>` fait du canal un exécuteur à l'intérieur des invités, ce
  que le 7ᵉ journal rend traçable. La mesure en creux de l'ép. 16 a été **retournée** plutôt que
  supprimée : le banc vérifie que le verbe qui exécute est `exec` et lui seul.
- **M3 — le producteur d'état existe déjà, mais il n'est ni déclenchable ni servi.**
  `marionnet-report.sh` (ép. 7) écrit un rapport qui porte **exactement** ce que M1 réclame :
  interfaces réelles, tables de routage v4 **et** v6, voisinage, `net.ipv4.ip_forward`, et le
  pare-feu sous forme **rejouable** (`iptables-save`). Mesuré : rien dans le hostfs tant que la
  machine tourne ; le rapport apparaît **à l'arrêt** (432 lignes) ; et `log r1 report` **refuse** —
  la liste des journaux est fermée à cinq.
  **Comblé (ép. 16)** : le déclencheur est un veilleur posé dans l'invité par l'épilogue, et la
  liste s'est ouverte à **six**.
- **M4 — une adresse fabriquée dans l'invité n'est nulle part côté hôte.** Le treeview `ifconfig` a
  bien une colonne « IPv6 address », mais elle porte le **déclaré** et ne s'alimente jamais depuis
  l'invité. Un correcteur ne peut donc même pas **nommer** la cible d'un `ping6`.
  **Comblé (ép. 16)** par le même chemin que M1 : le rapport porte `ip -o addr show`, donc les
  adresses réelles, `fe80::` comprises. Le treeview, lui, n'a pas bougé — et ne doit pas bouger :
  ce qu'il porte est ce que l'utilisateur a **déclaré**.

### 7.4 Les pièges mesurés (ils condamnent les raccourcis évidents)

- **`set -x` ne trace pas les redirections.** `echo 1 > /proc/sys/net/ipv4/ip_forward` ne laisse
  dans le journal que `echo 1` : un correcteur qui cherche `ip_forward` dans la trace ne le trouvera
  **jamais**, alors que la commande a bien tourné (le rapport de fin dit `net.ipv4.ip_forward = 1`).
  « La trace prouve la configuration » est donc **faux**, même quand tout passe par le `rc_config`.
- **`|| true` rend le journal muet.** Idiome courant d'un rc (`radvd || /etc/init.d/radvd start ||
  true`) : le trap `ERR` de l'épisode 1 ne se déclenche pas à gauche d'un `||`. Un échec **absorbé**
  ne laisse aucune trace — mesuré sur `radvd`, qui démarrait sans annoncer.
- **`rc-set` est refusé sur une machine allumée** (`forbidden_transition`) : on ne peut pas même
  **poser** une sonde en marche, et *a fortiori* pas la rejouer.
- **`log` ne sert que les cinq journaux nommés** : un fichier arbitraire écrit par l'invité dans le
  hostfs n'est pas servi (mesuré, avec le refus qui nomme les cinq).
- **`wait --ready` remonte UNE ligne libre écrite par l'invité** — donc un verdict *est* déjà
  remontable, mais une seule fois, au boot, et à l'initiative de l'invité seul.
- **Les ports ne se comptent pas pareil des deux côtés** : Marionnet nomme `port1…portN`, `vde` les
  numérote `0001…` — `port/setvlan 0 5` échoue en 1006. Une assertion sur « le port 2 » doit dire
  de quelle numérotation elle parle.
- **`iptables -L -vv` est illisible avec le backend `nft`** (pseudo-bytecode : `[ cmp eq reg 1
  0x32687465 ]`). Le rapport porte heureusement aussi `iptables-save` : c'est **cette** section
  qu'un vérificateur doit lire. Les sections `-L -vv` gardent leur intérêt sur un backend *legacy*
  (compteurs) — rien à corriger, mais à savoir.
- **Limite d'environnement** : `radvd` démarre dans l'invité, lit sa configuration, et n'émet
  **aucun** RA sur cet hôte (`sendmsg: Invalid argument`). L'autoconfiguration **globale** du § 2 de
  C5 n'est donc pas jouable ici — comme le `wireshark` live, c'est une limite à porter au chantier
  `marionnet-kernel-rootfs`, pas au vérificateur. Le § 1 de C5 (adresses **lien-local**) suffit à
  établir M4.

### 7.5 Les primitives que l'épisode 16 doit offrir

Aucune n'est inventée : chacune vient d'une affirmation d'un des cinq TP.

| Primitive | Verbe qui la sert | Statut |
|---|---|---|
| `state <c> == on\|off\|sleeping` | `ls` | disponible |
| `model <c>.<champ> == <v>` | `get` | disponible |
| `<c>:<if>` câblé à `<c2>:<port>` | treeview des câbles | disponible |
| `switch <sw> <table>` contient … | `switch-info` | disponible |
| `journal <c> <j>` contient / ne contient pas … | `log` | disponible |
| `journal <c> <j>` sans échec (`!! FAILED`) | `log` | disponible |
| `documents <c>` porte rapport / historique / terminal | `documents` | disponible |
| **état de l'invité** (adresses, routes, `ip_forward`, pare-feu) | `report`, puis `log <c> report` | disponible **depuis l'ép. 16** |
| **connectivité** (`ping`, `ssh`, un port ouvert) | `exec`, et `reaches` dans `mrn-verify` | disponible **depuis l'ép. 18** — écrite d'avance à l'ép. 17, rendue vivante par la capacité lue dans `help` |

> **Depuis l'épisode 17**, ces primitives ne sont plus seulement *disponibles*, elles sont
> **écrites** : chaque ligne du tableau est une famille d'assertions de `mrn-verify` (§ 4.16), et
> la dernière y figure aussi — sautée tant que le canal ne publie pas le verbe qui la porterait.

### 7.6 Ce qu'il faudra ajouter, et à quel prix

Trois voies, du moins cher au plus intrusif :

1. **Rapport à la demande** (*recommandé*) : le producteur existe et son format est déjà lisible ;
   ce qui manque est un **déclencheur**. Le hostfs étant le seul chemin de retour, il faudrait que
   le prologue de l'épisode 1 laisse dans l'invité une petite boucle qui exécute
   `marionnet-report` quand un fichier-drapeau apparaît, plus un 6ᵉ nom au verbe `log`. Coût :
   ~30 lignes de bash côté invité, une entrée de liste côté canal. Verdicts gagnés : M1, M3 et
   M4 en entier.
2. **Exécution à la demande** (`exec <c> <commande>`) : même mécanique, mais générique — elle
   apporte **M2** (donc la connectivité). Elle change en revanche la nature du canal, qui cesse
   d'observer pour commander l'intérieur des invités ; à trancher explicitement. **Tranchée, et
   livrée par l'épisode 18** (§ 4.17), le coût mesuré ayant été celui annoncé : la même mécanique,
   un veilleur généralisé plutôt qu'un second, et un journal de plus pour que ce que le canal
   injecte ne se confonde jamais avec le travail de l'étudiant.
3. **Ne rien ajouter** : le vérificateur se limite alors au modèle, aux traces et au rapport de
   fin. Il sait dire « la configuration a été tapée sans erreur » et « à l'arrêt, voici l'état »,
   jamais « à cet instant, m1 joint intrus ». Pour un mode examen c'est peut-être assez ; pour la
   mise au point d'un TP, non.

**Banc** : `_claude-local/bench/lab-pilot-bench.sh` rejoue toutes les lignes ci-dessus (dont chaque
« non observable », par la commande qui **échoue** à prouver).

## 8. Résultat et clôture (épisode 24, 2026-08-15)

### 8.1 Ce que le chantier laisse

Le fil est allé plus loin que son énoncé : parti de « journaliser jusqu'à l'intérieur des UML »,
il finit sur un TP réel qu'un enseignant construit, joue et **note**. Ce qui est versionné :

- **Dans l'invité, sans reconstruire aucune image** (déposés dans le hostfs par
  `make_hostfs_content`, embarqués par `INCLUDE_AS_STRING`) : `bin/scripts/marionnet-relay.00-journal.sh`
  et son épilogue `…zz-journal.sh` (indissociables), `marionnet-report.sh` (le rapport),
  `marionnet-watch.sh` (le veilleur, qui sert le rapport à la demande **et** l'exécution) et
  `marionnet-terminal-record.sh` (le terminal de l'étudiant, enregistré).
- **Dans Marionnet** : **sept journaux** servis par un seul verbe de lecture, l'instantané des
  tables d'un switch, le rapport à la demande, l'exécution dans un invité, et le **mode examen
  réanimé** — qui archive, et qui **refuse** désormais ce qui détruirait sans archiver (ép. 22),
  la sortie d'un projet valant enregistrement (ép. 23).
- **Pour qui note** : `useful-scripts/mrn-verify` (assertions `.mrv`, trois verdicts),
  `doc-src/teacher-guide.md`, `doc-src/exam-mode.md`, le § 11 de `doc-src/scripting/README.md`,
  `doc-src/lab-design-skill.md` (+ le wrapper `.claude/skills/marionnet-lab-design/`) et le TP
  complet `doc-src/labs/session-7/`.

L'**invariant transverse** hérité de `pilotage-par-script` a tenu du premier au dernier épisode et
s'est même étendu : la grammaire a une seule source de vérité — le serveur — et ce n'est plus
seulement le **vocabulaire** qu'on lui demande, c'est la **capacité** (ép. 17). Là où la
documentation devait tout de même apprendre quelque chose, elle **cite et fait vérifier sa
citation** (ép. 19), ou bien elle ne cite pas : ses exemples sont des **gestes joués** dont la
couverture se mesure par l'exécution (ép. 21).

### 8.2 Ce que le chantier n'a pas fait, et pourquoi

Aucun **attribut persisté** n'a été ajouté : le format `v3` n'a pas été rouvert. Le collecteur est
toujours actif, l'enregistrement de session reste **sur option** (`--console-log`,
`--terminal-log`, implicites en `--exam`). Restent délibérément dehors : le flux d'événements du
switch (mis en réserve par D4), l'observabilité des **hubs** (aucune socket de management), et un
rapport plus riche que celui de l'épisode 7 — sujet à part entière, dont l'épisode a livré
l'endroit où il viendra se brancher.

### 8.3 Où sont partis les défauts qui survivent au chantier

Le § 6 reste l'exposé détaillé. Comme ce document devient une archive, ce qui doit rester **trouvable**
sans lui a été reversé :

| Défaut | Parti vers |
|---|---|
| `wait --ready` ment au second démarrage | `docs/TODO.md` |
| un `rc-set` sur un **switch** n'est pris qu'au premier démarrage | `docs/TODO.md` |
| le rapport d'arrêt n'est pas garanti | `docs/TODO.md` |
| deux sessions Marionnet simultanées partagent l'adresse hôte de leurs taps | `docs/TODO.md` |
| les trois chaînes non traduites (textes d'aide de `world_bridge`) | chantier `modernisation-world-bridge` |
| l'erreur de glob des images sans `<image>.relay` | chantier `marionnet-kernel-rootfs` |
| l'installation des clients du canal et de la documentation d'usage | chantier `modernisation-installation-marionnet` (§ 2.4 ter) |

Deux entrées du § 6 sont **tombées à la clôture** : l'i18n de l'épisode 22, faite depuis
(`5161c49`), et les « titres traduits à moitié », qui étaient un **artefact de mesure** — un
binaire lancé depuis l'arbre de développement lit le catalogue du Marionnet **installé sur la
machine** (défaut déjà consigné au `docs/TODO.md`). Le reste du § 6 est fait de compromis assumés
(la page rendue vit deux minutes, le veilleur se réveille une fois par seconde, le *quoting* d'une
commande composée) ou d'une observation non instruite (le prompt de login absent du journal
`terminal` d'une trixie), gardée ici faute d'avoir été reproduite ailleurs.

### 8.4 S'il fallait rouvrir

Deux des défauts reversés — `wait --ready` et le `rc-set` d'un switch — sont la **même** famille :
un état capturé à la création d'un device simulé qui **survit à l'extinction**. Ils se tranchent
avec l'automate d'état en tête (`docs/refonte-automate-composants.md`), pas depuis ce chantier-ci.

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

### 2026-08-12 — Épisode 10 : le rapport rendu, et l'omission qu'il fallait rendre visible

**Ce que l'épisode a livré** (détail : § 4.10) : le rapport Markdown de l'épisode 7 s'ouvre
**rendu** dans le navigateur au double-clic, et sa **source** est à un geste — entrée de menu
contextuel *« Show and edit the source »*, fenêtre GtkSourceView coloriée, éditable, écrite en
retour dans le document du projet. Conversion **interne** (cmarkit), lecteurs enfin vérifiés,
extension conservée à l'import.

**La conception s'est jouée sur un mot : *déterminisme*.** Le premier plan cherchait un
convertisseur sur l'hôte (`pandoc`, `cmark`, `markdown_py`…) avec repli sur l'éditeur de texte.
Deux objections l'ont écarté, et elles ne valent que parce que le document peut être **noté** :
la même archive rendrait **différemment** selon la machine qui l'ouvre, sans que rien sur la page
ne le dise ; et `report.md` est écrit **dans l'invité**, donc sur une machine que l'étudiant
contrôle, si bien qu'un `<script>` y tournerait dans la page du correcteur. `cmarkit` (ISC, aucune
dépendance) rend la même page partout et `~safe:true` neutralise le HTML brut. L'échappatoire
reste, mais **explicite** : `MARIONNET_MARKDOWN_TO_HTML` remplace la conversion par une commande
externe — une décision de l'exploitant, plus un effet de bord du parc installé.

**Ce que la mesure a retourné.** `~safe:true` n'**échappe** pas le HTML brut : il le **jette**, en
laissant `<!-- CommonMark HTML block omitted -->` — un commentaire, donc **invisible** dans un
navigateur. Le correcteur aurait lu un rapport troué sans le savoir. L'omission est donc rendue
visible (une ligne rouge, à la place), et ce que l'invité a réellement écrit reste atteignable par
la vue *source* du même épisode. Le motif suit un rendu que la bibliothèque documente comme
instable : s'il change, on retombe sur le commentaire invisible — une dégradation, pas une casse —
et le banc rougit, ce pour quoi il assert sur le **marqueur visible** et non sur le commentaire.

**Deux défauts antérieurs sont tombés en chemin**, tous deux nécessaires au discriminant. (1) Le
document importé perdait son extension (`document-XXXXXX`) : rien, à l'affichage, ne distinguait
un rapport Markdown d'un texte quelconque — la colonne `Format` disant « text » pour les deux
depuis l'épisode 7, **exprès**, pour qu'aucune valeur neuve n'atteigne un `.mar`. L'import
conserve désormais l'extension ; un `.mar` d'avant cet épisode garde le comportement d'avant.
(2) `MARIONNET_HTML_READER` valait **`galeon`** dans `etc/marionnet.conf` *et* dans le code — un
navigateur mort vers 2010 — et `display` lance `«lecteur 'fichier' &»`, si bien qu'un lecteur
absent ne produisait **rien du tout**, en silence. Les lecteurs sont maintenant vérifiés avant
d'être lancés, avec un repli sur `xdg-open` et quelques usuels : le correctif répare aussi le
`marionnet.conf` déjà installé de qui n'y a jamais touché.

**Sur le choix rendu/source**, l'ergonomie a été tranchée dans le sens du geste le plus fréquent :
pas de boîte de dialogue à chaque ouverture (un clic de plus, à chaque lecture, pour une réponse
presque toujours la même), mais **deux gestes** — double-clic pour lire, menu contextuel pour la
source. L'entrée n'apparaît que sur une ligne Markdown (le prédicat du menu, `treeview.ml:853`,
ne construit même pas l'item quand il est faux) : rien ne change pour les autres documents.

**Mesures.** Banc neuf `markdown-bench.sh` : **47 assertions, 0 échec**. Sa méthode est le point
notable — il **extrait** le module `Markdown_rendering` de `treeview_documents.ml`, lui donne une
doublure de ses trois dépendances (Log, Configuration, UnixExtra) et le compile : ce sont les
**vraies lignes** qui répondent, hors GUI, là où un banc qui paraphraserait le code mentirait dès
la première divergence. Il couvre la reconnaissance par le nom, l'enveloppe (charset, titre
échappé, accents), le tableau (mode non strict), l'omission signalée, l'échappatoire et ses trois
replis (commande absente, en échec, muette), et le fichier rendu (hors projet, `TMPDIR` honoré,
jamais fatal).

**Non-régression, tous verts au premier passage** : `exam-bench.sh` **74/74**, `doc-bench.sh`
**62/62**, `journal-bench.sh` **165/165**. Et l'`exam.mar` que le premier laisse derrière lui porte
la preuve du second correctif, celui de l'import : ses quatre documents s'appellent désormais
`document-….md`, `document-….log` et `document-….text`, là où ils n'avaient aucune extension —
la colonne `Format` disant toujours « text » pour les quatre. Reste le câblage GUI lui-même
(double-clic → navigateur, menu contextuel → source), joué **à la main** : aucun outil de synthèse
d'événements X n'est installé sur cette machine, et fabriquer une automatisation de clic pour un
seul geste coûtait plus qu'il ne prouvait.

**Une dépendance de build s'ajoute**, la troisième après `yojson` et `base64` : `cmarkit`.
Contrairement aux deux autres elle n'a **aucun paquet Debian/Ubuntu** (vérifié le 2026-08-12) —
elle vient d'opam ou devra être *vendored*. Noté dans le `Makefile` à l'intention du chantier
`modernisation-installation-marionnet`, qui devra la répercuter dans `Build-Depends`,
`BuildRequires` et l'image Docker.

### 2026-08-12 — Épisode 11 : la page que le navigateur ne pouvait pas lire

**Le geste manquant a parlé.** L'épisode 10 était committé et son banc vert ; restait le
double-clic, que rien n'automatisait. Joué avec `xdotool`, il a échoué sur *« Erreur de chargement
de la page »* : le Firefox d'Ubuntu est un **snap**, et `snap-confine` lui donne un `/tmp`
**privé**. La page rendue, écrite dans le `/tmp` de l'hôte, n'existait pas pour lui. Le profil
AppArmor dit le reste : `owner @{HOME}/[^s.]**` — le home **sans ses fichiers cachés** — donc
`~/.marionnet/` n'aurait rien arrangé.

**Le premier correctif (un répertoire non caché du home) a été refusé par l'auteur**, et à raison :
créer un répertoire visible chez l'utilisateur pour un fichier recalculé à chaque lecture, à cause
d'un choix d'empaquetage d'une distribution, c'est céder deux fois. Quatre pistes ont été mises sur
la table ; celle retenue supprime la question au lieu de la déplacer.

**Livré** (détail : § 4.11) : la page n'est **écrite nulle part**. Elle est servie sur
`127.0.0.1`, port éphémère, chemin = jeton de 128 bits, par `Network.stream_inet4_server`
(`~no_fork:()`, `~range4:"127.0.0.1/32"`). Le lecteur reçoit une URL là où il recevait un chemin —
`display` n'a pas changé d'une ligne. Le serveur se retire seul : 5 s après que la page a été
prise, 2 min au plus. Repli sur le fichier temporaire si la boucle locale échoue.

**Ce que l'épisode enseigne sur la méthode** : le banc de l'épisode 10 ne pouvait pas voir ce
défaut. Il vérifiait que la page existe et qu'elle est hors du projet — c'était vrai. Ce qu'aucune
assertion sur notre propre processus ne pouvait montrer, c'est qu'un **autre programme, confiné,
y accède**. Le banc a reçu la mesure ensuite, mais l'ordre compte : il ne remplace pas le premier
passage réel.

**Mesures.** `markdown-bench.sh` : **50 assertions, 0 échec** (47 avant l'épisode) — dont la forme
de l'URL, la page réellement servie et son `Content-Type`, le **404** sur un chemin sans le jeton,
le **retrait automatique** du serveur, et le home resté propre. Le banc lie maintenant le vrai
`ocamlbricks` construit par dune (le module extrait utilise `Network` : il n'y avait plus rien à
simuler). Et le bout en bout GUI, cette fois **joué** : double-clic → rapport affiché rendu ;
entrée de menu présente sur la seule ligne Markdown ; source coloriée ; `Valider` écrit
l'annotation (accents compris) dans le document du projet et rétablit la lecture seule ;
`Annuler` ne change pas un octet. Deux pièges de la conduite au clavier, notés pour la prochaine
fois : la colonne **Titre est éditable**, donc un clic y ouvre une saisie et le double-clic
n'active jamais la ligne (viser la colonne **Icône**) ; et un menu Gtk+ est une **fenêtre X à
part**, invisible d'une capture de la fenêtre principale.

### 2026-08-12 — Épisode 12 : la course de l'extinction, et le droit d'écrire

**Deux défauts rapportés par l'auteur** après un `--exam` réel à deux machines (détail : § 4.12).

**La course.** L'onglet Documents portait des « Please edit this » — le défaut d'une colonne — et
des auteurs incohérents : `import_exam_documents` tourne dans le thread d'extinction de chaque
machine, et deux extinctions simultanées écrivaient dans le même `GtkTreeStore`. Le geste **entier**
passe désormais par `GMain_actor.apply_extract` : ce qui ne doit pas s'entrelacer est la séquence,
pas l'appel isolé. C'est la règle du dépôt appliquée à un endroit qui y avait échappé.

**Le droit d'écrire.** La fenêtre source de l'épisode 10 était éditable pour tout le monde ; en mode
examen, c'est l'**étudiant** qui est devant l'écran. `Gui_source_editing.window` reçoit un
`?read_only` (vue non éditable, un seul bouton qui ferme) et le treeview le passe sous `--exam` ;
le libellé du menu change avec lui. Hors examen, rien ne change : annoter un rapport reste ce pour
quoi le geste existe.

**Mesures.** `exam-race-bench.sh` (neuf) : deux machines, extinctions lancées en parallèle,
8 documents, aucun champ défaillant, tous les auteurs « - ». **Et une honnêteté à consigner** : ce
banc ne reproduit pas la course (les deux archivages tombent à ~5 s d'écart ; il passe aussi sans
le correctif, vérifié en le désactivant). Le déclencheur réel est « Tout arrêter » dans la GUI, qui
éteint tout d'un coup ; le banc vaut comme non-régression, pas comme discriminant.

### 2026-08-12 — Épisode 13 : les mots du chantier, dans les douze langues

**Le dernier défaut visible du § 6** (détail : § 4.13). Le code appelait `s_` ; c'est le catalogue
qui ignorait sept `msgid` — les quatre étiquettes des documents archivés (`Console`, `Console of `,
`Terminal`, `Terminal of `), le titre `Source of ` et les **deux** libellés de menu de l'épisode 12.
Aucun `.ml` n'a été touché.

**Le piège de l'épisode a été l'outil, pas la langue.** La première régénération du POT n'a produit
**aucun diff** alors que sept chaînes manquaient : `gettext-all-ml-pot-files` fabrique un instantané
des sources par **liens durs**, et `cp -l` échoue quand la cible existe — le second passage
ré-extrayait donc, en silence, l'instantané du 9 août. Le `Makefile` efface maintenant
`_build/pot/…` avant de le refaire. Sans cette mesure, l'épisode aurait conclu « rien à faire ».

**Traductions.** Registre calqué, langue par langue, sur les chaînes sœurs déjà traduites du même
treeview. Deux écarts assumés et consignés : le **turc** prend la forme « X : » (langue
postpositionnelle, code qui concatène un préfixe), et **es/pt/pt_BR** disent « code source » —
« fuente/fonte » seul désignant aussi une police de caractères.

**Mesures.** POT : 379 → **386** entrées, **7 ajoutées, 0 retirée**. `msgmerge
--no-fuzzy-matching` (donc aucune traduction devinée) : les douze catalogues passent de
*375 traduites / 3 non traduites* à **382 / 3**, **0 *fuzzy***, `msgfmt -c` propre sur les douze —
et **aucune entrée obsolète nouvelle** (2 avant, 2 après). `dune build` : succès, douze `.mo`
recompilés. Preuve que ce sont bien les **catalogues compilés** qui portent les mots, et non les
seuls `.po` : `msgunfmt` sur `fr.mo`, `it.mo`, `ru.mo`, `tr.mo` rend les sept chaînes, espaces
finaux compris (`Console de `, `Konsol: `). Les **3** non traduites restantes sont celles de
`world_bridge`, hors périmètre par décision de l'auteur.

### 2026-08-12 — Épisode 14 : la capture qui n'attrapait rien sur wheezy

**Le dernier point d'ombre du § 6** (détail : § 4.14) : depuis l'épisode 7, on savait que
`rc_config.log` ne portait, sur `debian-wheezy-08367`, que ses trois lignes d'en-tête — sans savoir
pourquoi, alors que `boot.log` était complet sur la même image. Clore le chantier sur cette
inconnue n'était pas possible : c'est le livrable de l'**épisode 1** qui était troué.

**La sonde a dû sortir du chemin qu'elle mesurait.** Sur cette image, la console de l'invité part
dans un xterm et non dans le processus UML : ce qui échappe à la capture ne se retrouve donc nulle
part, pas même dans le journal de console de l'épisode 6. La sonde a été posée dans le `rc_config`
du scénario (aucun fichier du dépôt modifié) et **redirigée explicitement** vers un fichier du
hostfs. Un seul boot a suffi.

**Cause racine.** `tee` est atteint par une **substitution de processus**, que bash ouvre par
`/dev/fd/<n>` **dans le shell appelant**. L'image de 2013 n'a pas `/dev/fd` quand elle tourne : son
lien symbolique est masqué par le tmpfs monté sur `/dev`, et son init ne le remet pas. L'`exec`
échouait donc **en entier** — `2>&1` compris, les redirections s'appliquant de gauche à droite —,
le shell gardant ses descripteurs d'origine et poursuivant sans rien dire. Ce qui explique enfin
les trois symptômes ensemble : le `set -x` « fonctionnait » (vers l'ancien descripteur), les deux
descripteurs pointaient sur **deux pipes distincts**, et le journal s'arrêtait à ce qui avait été
écrit avant.

**La garde ne posait pas la bonne question.** `type -p tee` répond `/usr/bin/tee` : `tee` est là,
c'est la substitution qui ne s'ouvre pas. Le prologue **répare** `/dev/fd` s'il manque (un tmpfs :
aucune image, ni même le COW, n'est écrite) puis **mesure** la substitution — `( exec 9> >(cat
>/dev/null) )` — au lieu de la supposer ; et la branche de repli **nomme sa raison**. Un seul
fichier touché, `bin/scripts/marionnet-relay.00-journal.sh` ; l'épilogue est inchangé.

**Mesures.** Même image, même scénario fautif : `# capture: tee (console and journal)`, journal de
**39 lignes** au lieu de 3, avec la trace, la sortie et `!! FAILED (status 2)`. `journal-bench.sh` :
**171 assertions, 0 échec** (165 + 6 neuves dans le bloc J8) ; `exam-bench.sh` : **74 assertions,
0 échec**, inchangé. Le tableau du § 4, qui avait sauté la ligne de l'épisode 13, est remis
d'aplomb (les deux épisodes optionnels deviennent 15 et 16).

### 2026-08-12 — Épisode 15 : le corpus des TP, et ce que le canal ne sait pas encore prouver

**Pourquoi cet épisode existe** (détail : § 7). L'auteur veut le skill de conception de TP et ne
compte pas y renoncer. Or D6 dit *pourquoi* il est optionnel et **de fin** : sans couche de verdict
vérifiable, un skill n'émet que du bash généré — invérifiable, non rejouable, différent à chaque
génération. Et inventer les assertions du vérificateur en chambre serait exactement la faute que
`lazy-senior` interdit. D'où cet épisode intercalé : une **sonde** qui spécifie le vérificateur à
partir de TP **réels**, et qui mesure au lieu de raisonner. Renumérotation : 16 = le vérificateur,
17 = le skill.

**Le corpus.** Cinq TP, dont **deux vrais** : la séance 7 de l'auteur (routage, filtrage,
SNAT/DNAT) et la séance 10b (IPv6 : autoconf, routage, filtrage). Leur corrigé de pare-feu,
`my_firewall.sh`, n'est pas réécrit : le banc le **lit** et le pose comme `rc_config` du routeur,
avec la seule adaptation de la cible du DNAT à une maquette réduite (`m1 — h1 — r1(3 ports) — h3 —
intrus`). Le risque « userland » annoncé au plan est tombé avant d'être couru : `debugfs` sur les
images, sans les monter, montre `iptables`, `ip6tables`, `radvd`, `nginx`, `sshd`, `tcpdump` — tout
est là, y compris sur la wheezy de 2013.

**Ce que la mesure a retourné.** Trois fois, et jamais dans le sens attendu :

1. **`set -x` ne trace pas les redirections.** Le plan tenait « la trace du rc prouve la
   configuration » pour une preuve indirecte mais solide. Elle ne l'est pas : `echo 1 >
   /proc/sys/net/ipv4/ip_forward` ne laisse dans le journal que `echo 1`. Un correcteur qui cherche
   `ip_forward` ne le trouvera **jamais**, alors que le rapport de fin dit `net.ipv4.ip_forward =
   1`. La trace prouve ce qui a été **appelé**, pas ce qui a été **écrit**.
2. **`rc-set` est refusé sur une machine allumée** (`forbidden_transition`) — le banc attendait un
   succès sans effet. Conséquence plus dure que prévu : on ne peut pas même **poser** une sonde en
   marche.
3. **Le producteur d'état existe déjà et il est bon.** `marionnet-report.sh` (ép. 7) porte les
   interfaces réelles, les tables de routage v4 **et** v6, le voisinage, `ip_forward`, et le
   pare-feu sous forme **rejouable** (`iptables-save` — les sections `-L -vv`, elles, rendent du
   pseudo-bytecode `nft` illisible). Il ne manque donc pas un producteur : il manque un
   **déclencheur** (le rapport n'apparaît qu'à l'arrêt) et un **service** (`log r1 report` refuse,
   la liste des journaux est fermée à cinq).

**Résultat.** Le § 7 tient les cinq tableaux d'affirmations, les quatre **manques** (M1 l'état d'un
invité, M2 l'exécution dans un invité, M3 le rapport ni déclenchable ni servi, M4 l'adresse
fabriquée dans l'invité que le treeview ignore), les sept **pièges** qui condamnent les raccourcis,
la liste **fermée** des primitives de l'épisode 16 — aucune inventée — et les trois voies chiffrées
pour combler les manques. La recommandation est la moins intrusive : **rapport à la demande**
(~30 lignes de bash côté invité, une entrée de liste côté canal), qui donne M1, M3 et M4 sans faire
du canal un exécuteur de commandes dans les invités (ce que serait `exec`, seul chemin vers M2).

**Limite d'environnement, mesurée deux fois** : `radvd` démarre, lit sa configuration, et n'émet
aucun RA (`sendmsg: Invalid argument`). L'autoconfiguration **globale** du § 2 de C5 n'est pas
jouable sur cet hôte — à porter à `marionnet-kernel-rootfs`, comme le `wireshark` live. Le § 1 du
même TP (adresses **lien-local**) suffit à établir M4, et il est même plus fidèle à l'énoncé.

**Mesures.** Banc neuf `_claude-local/bench/lab-pilot-bench.sh` : **75 assertions, 0 échec**
(38 sans UML avec `E2E=0`). Les trois premiers passages ont mis en défaut le **banc** — jamais le
canal : filtres `jq` sur `.entries` au lieu de `.tables[].entries`, ports `vde` numérotés à partir
de 1, champ `port_no` et non `ports`, et les trois attentes fausses ci-dessus. Aucun fichier du
dépôt n'a été modifié en dehors de cette documentation.

### 2026-08-12 — Épisode 16 : le rapport à la demande, et le déclencheur qui manquait

**Ce que l'épisode livre** (détail : § 4.15). La **voie 1** du § 7.6, choisie parce que l'épisode 15
avait montré qu'il ne manquait **ni producteur ni format** : `marionnet-report.sh` porte déjà
l'état qu'un correcteur veut lire, il ne s'exécutait qu'à l'arrêt et personne ne le servait. Sont
livrés le **veilleur** (`bin/scripts/marionnet-report-watch.sh`, déposé dans le hostfs et démarré
par l'épilogue), le protocole à trois fichiers (`report.request` / `report.md` / `report.done`), le
verbe **`report <component> [--timeout=<s>]`** et le **sixième journal**, `report`, servi par `log`.
M1, M3 et M4 sont comblés ; **M2 reste ouvert, par décision** — `exec` ferait du canal un exécuteur
dans les invités.

**Ce que la mesure a retourné.** Quatre fois, et trois d'entre elles ont mis en défaut le **banc**,
jamais le canal :

1. **La forme évidente de l'unité systemd ne démarre pas.** Écrite avec les dépendances par défaut
   et un `systemctl start` bloquant, l'unité du veilleur ne tourne tout simplement pas : la trixie
   boote, `boot.log` est complet, et `report` expire parce que personne ne veille. Nous sommes
   sourcés par le relais, que systemd est lui-même en train de démarrer — la demande est donc un
   ordonnancement dans une transaction déjà en cours. Le veilleur n'a besoin d'**aucun**
   ordonnancement (il attend un fichier) : `DefaultDependencies=no` et `--no-block`. Et, parce que
   la première ligne retire aussi ce qu'on **veut** garder, `Conflicts=shutdown.target` remet le
   veilleur à l'arrêt avant que le rapport de fin soit pris.
2. **Le marqueur de `wait --ready` est écrit par le SCÉNARIO**, jamais par le relais (§ 4.7). Un
   banc dont le `rc_config` l'oublie attend 240 s pour rien — et l'attente ne prouve alors rien du
   tout sur l'épisode.
3. **`fe80::` n'existe que sur une interface montée.** Le scénario faisait `ip addr add` sans
   `ip link set up` : pas d'adresse lien-local, donc pas de discriminant M4. Ce n'est pas un détail
   d'IPv6 — c'est **exactement** la propriété qu'on veut montrer, une adresse que *personne* n'a
   déclarée et que l'invité fabrique.
4. **L'ordre de `.available` n'est pas celui de `help`.** `journals_of` concatène les journaux du
   hostfs *puis* les deux que Marionnet écrit lui-même, donc `report` arrive **avant** `console` et
   `terminal` dans la liste d'un composant, alors que `help` le publie en sixième. Les deux sont
   justes : l'un dit le vocabulaire, l'autre ce que *ce* composant a.

**Le discriminant, en une ligne.** Sur la même machine, au même instant, par le même verbe :
`log m1 rc_config` ne contient pas `ip_forward` (la trace ne voit pas les redirections, § 7.4) et
`log m1 report` dit `net.ipv4.ip_forward = 1`. Le rapport mesuré porte aussi la règle de SNAT sous
forme rejouable (`iptables-save`), l'adresse posée par le rc, et l'adresse lien-local que le
treeview `ifconfig` ignore.

**Mesures.** Banc neuf `_claude-local/bench/report-bench.sh` : **51 assertions, 0 échec**, dont le
bout en bout sur une trixie démarrée par le canal. Bancs existants rejoués : `journal-bench.sh`
(statique, **97**, 0 échec), le banc de complétion (**60**, 0 échec) et `exam-bench.sh` (**74**,
0 échec — le rapport d'arrêt et l'archivage du mode examen sont intacts). Les trois
ont demandé la **même** correction, et une seule : la liste des journaux, passée de cinq à six.
C'est la règle d'unicité qui joue à plein — le **code** de la complétion n'a pas été touché du
tout (12ᵉ application), seul son *banc* codifiait la liste ; ce sont les bancs qui portaient une
copie, jamais les clients.

### 2026-08-12 — Épisode 17 : le vérificateur déclaratif, et le verdict qu'il fallait ne pas rendre

**Point de départ, et une numérotation à remettre d'aplomb.** Le tableau du § 4 réservait la case
16 au vérificateur ; l'épisode 16 y a livré le rapport à la demande, qui n'était pas prévu là. La
case a donc été rendue à son contenu réel, et la suite renumérotée : **17** ce vérificateur, **18**
`exec` (M2, que l'auteur a tranché en rouvrant le chantier), **19** le skill de conception de TP.
Écrire le skill avant le vérificateur l'aurait fait émettre du bash `mrnctl` + `jq` — c'est-à-dire
un corrigé par TP, invérifiable et non rejouable : exactement ce que la ligne 172 déconseillait
depuis l'épisode 15.

**Ce qui est livré.** `useful-scripts/mrn-verify` (neuf, ~560 lignes de bash, installable à côté de
`mrn-check`), la complétion (`_mrn_verify_completion` — les options du **client**, la seule chose
qui lui appartienne), le § 14 neuf du guide `doc-src/scripting/README.md` (« Asserting a lab »,
d'où une renumérotation 14→15, 15→16), deux exemples versionnés — `examples/lab.mrv`, le pendant
assertionnel de `lab.mrn`, et `examples/06-assert-a-lab.sh` — et le banc neuf
`_claude-local/bench/verify-bench.sh`. **Aucun `.ml` touché** : l'épisode n'ajoute pas un verbe au
canal, il écrit ce que le canal sait déjà répondre. Détail de conception : § 4.16.

**Quatre corrections par la mesure.** La première seule aurait suffi à justifier le banc :

1. **Sous `set -e`, l'analyseur de lignes arrêtait tout, en silence.** `parse_line` rendait le
   statut de sa dernière garde (`check_endpoint … || return`), et la boucle de lecture l'appelle
   comme une commande simple : une ligne fautive terminait le processus. Le rapport paraissait
   seulement **plus court** — quatre diagnostics au lieu de cinq, et pas de ligne de résumé. Ce
   n'est pas le mécanisme qui mentait, c'est une **absence** qui ne se voit pas : le banc l'a vue
   parce qu'il **compte** les erreurs attendues au lieu de les lire.
2. **Les entrées d'une table de switch ne sont pas plates** : les ports d'un VLAN sont une liste
   d'objets, donc `select(.port == 3)` sur l'entrée ne trouve rien. D'où l'aplatissement en paires
   `chemin=valeur` (index de liste supprimés) et la notation `ports.port=3` — et, quand une clé
   n'existe nulle part, la liste de celles qui existent, prise **dans la réponse**.
3. **Un `rc-set` sur un switch déjà démarré une fois est ignoré au démarrage suivant.** Défaut du
   dépôt, pas de l'épisode : le contenu du rc est capturé à la création du device simulé, qui
   survit au `poweroff` ; `rc-get` rend pourtant le nouveau contenu. Consigné au § 6 ; le banc
   utilise **deux switchs** plutôt que de mélanger deux mesures.
4. **Les titres du treeview `documents` passent par gettext** (piège déjà connu, réappliqué) :
   l'assertion s'appuie sur le **nom du composant**, qui n'est jamais traduit.

**Le discriminant, en deux lignes du même fichier.** Sur la même machine, au même instant :
`journal m1 rc_config contains ip_forward` → **FAIL**, `report m1 says ~ net[.]ipv4[.]ip_forward
*= *1` → **PASS**. La configuration a bien tourné : c'est la trace qui ne peut pas le dire (§ 7.4).
Un corrigé écrit sur la première ligne recalerait un étudiant qui a tout juste.

**Le second discriminant se mesure sans UML** : le même `.mrv`, contrôlé contre l'instantané
complet de `help` puis contre le même instantané **amputé** du verbe `report`, ne dit pas la même
chose — la capacité de l'outil vient de la grammaire, pas d'une table écrite dedans. C'est ce qui
garantit que l'épisode 18 rendra `reaches` vivante **sans** rouvrir ce fichier.

**Mesures.** `verify-bench.sh` : **84 assertions, 0 échec** (63 sans UML), dont le § V6 où la doc
est vérifiée par l'outil lui-même — le `.mrv` **cité** par le guide est extrait du Markdown et
contrôlé, l'exemple versionné est joué **tel quel** sur la session du banc, et `06-assert-a-lab.sh`
est exécuté tel quel (11ᵉ application de la règle d'unicité, sous la forme établie à l'épisode 9 :
citer, et faire vérifier la citation).

**Non-régression** : `dune build` vert (aucun `.ml` n'a bougé, on le prouve), banc de complétion
**60**, `doc-bench.sh` **62**, `journal-bench.sh` **97**, `report-bench.sh` **25**,
`exam-bench.sh` **33** — 0 échec partout, les trois derniers en `E2E=0` (rien de ce qu'ils
mesurent avec une UML n'est touché par l'épisode). `doc-bench.sh` a demandé la **même** correction
que les trois bancs de l'épisode 16 et qui lui avait échappé : cinq journaux → six. Le guide, lui,
portait encore la trace du même oubli — « the five journals above are traces », alors que son
tableau en cite six depuis l'épisode 16 : ce sont les **cinq autres**, `report` étant un état et
non une trace, ce que la phrase dit désormais.


### 2026-08-12 — Épisode 18 : le canal exécute, et ce que cela seul peut prouver

**Ce que l'épisode livre.** Le verbe `exec <composant> <ligne de commande> [--timeout=<s>]`, M2 du
§ 7.3 — le dernier manque, laissé ouvert par l'épisode 16 et tranché ici pour lui-même. Détail
complet au § 4.17 ; l'essentiel tient en une phrase : les huit verbes qui le précèdent
**observent**, celui-ci **commande** l'intérieur d'un invité, et c'est le seul chemin vers une
affirmation de **connectivité**.

**La conception n'a rien inventé.** Le protocole de fichiers de l'épisode 16 a été repris tel
quel (le hostfs est le seul chemin de retour, D1), le veilleur a été **généralisé** au lieu d'être
dupliqué — d'où le renommage `marionnet-report-watch.sh` → **`marionnet-watch.sh`**, parce que le
§ 6 chiffrait déjà le prix du sondage : un réveil par seconde et par invité —, et la seule
addition au protocole est un **identifiant** de requête : un rapport est idempotent, une commande
ne l'est pas.

**Trois virages par la mesure, tous dans le transport de la ligne de commande.**

1. **Les options sont reconnues où qu'elles soient** dans une requête. `exec m1 ls --all` aurait
   donc exécuté `ls` et avalé `--all` **en silence**. Deux corrections indissociables :
   `parse_request` reconnaît le séparateur `--` (comme tout outil Unix), et `exec` **refuse** une
   option inconnue — le refus est ce qui rend le séparateur découvrable.
2. **Le quoting ne survit pas au shell de l'appelant** — mesuré au banc de documentation, sur la
   paire la plus courte possible : `mrnctl exec m1 -- sh -c 'exit 7'` rend **0** (le shell du
   client a mangé les quotes, l'invité a exécuté `exit`), `mrnctl exec m1 "sh -c 'exit 7'"` rend
   **7**. Le canal est orienté ligne : une commande composée se passe comme **un seul argument**.
   Écrit dans le guide, avec la mesure.
3. **Borner la commande et l'attente avec la même valeur rend le dépassement irrapportable** :
   l'attente expirerait à l'instant où l'invité tue la commande, et le client n'apprendrait que ce
   qu'il sait déjà (pas de réponse). D'où 15 s de grâce, et une réponse qui porte `timed_out:
   true`, le statut 124 et ce que la commande avait produit avant d'être tuée.

**Un défaut de la fiche mémoire, corrigé par la mesure.** Elle annonçait que l'épisode 18 rendrait
`reaches` vivante « sans rouvrir `mrn-verify` ». Le **mécanisme de capacité** de l'épisode 17 a
bien fonctionné seul (le verbe est cherché dans `help`), mais le **corps** de la famille n'était
pas écrit : après le test de capacité, l'outil rendait un `SKIP` inconditionnel. Le corps a donc
été écrit — il résout l'adresse de la cible par son **rapport** (M4 : le seul endroit où une
adresse réellement configurée existe), puis joue un `ping` par `exec` — et la grammaire s'ouvre à
une **adresse écrite**, pour une cible que le projet ne modélise pas. Le troisième verdict garde
son sens : une cible éteinte donne un `SKIP` qui nomme ce qui manque — l'adresse, pas le réseau.

**Le 7ᵉ journal** `exec` porte ce que le canal a fait exécuter (commande, date, statut ; jamais la
sortie, servie dans la réponse). Sa raison est la **notation** : ce que le correcteur injecte ne
doit jamais se confondre avec ce que l'étudiant a tapé (`commands`). Deux écrivains, deux
fichiers — la règle de l'épisode 8.

**Le discriminant, sur la même session au même instant.** `reaches m1 h3` → **PASS** ; on éteint
h3 ; `reaches m1 h3` → **FAIL** — et entre les deux, le rapport de m1 est **inchangé**. Un rapport
décrit un état, jamais une accessibilité : c'est précisément ce que l'épisode 16 ne pouvait pas
combler.

**Mesures.** `exec-bench.sh` neuf : **60 assertions, 0 échec** (30 sans UML). Bancs existants mis
à jour et rejoués : `doc-bench.sh` **66/0** (dont l'exemple neuf `07-exec.sh`, joué tel quel),
`verify-bench.sh` **84/0** (complet, avec UML), `journal-bench.sh` **171/0** (complet),
`completion-bench.sh` **60/0**, `report-bench.sh` **25/0** sans UML, `exam-bench.sh` **74/0**,
et les trois bancs des clients (`check` **32/0**, `mrn2sh` **32/0**, `ctl` **36/0**) — ces derniers
parce que le séparateur `--` touche `parse_request`, donc **toute** la grammaire, et non le seul
verbe neuf. Erreur de conduite à retenir : `exam-bench.sh` a d'abord rendu **3 échecs**, tous sur
le rapport de fin, parce qu'il tournait **en parallèle** d'un autre banc à UML — l'invité s'éteint
alors au milieu du rapport, le piège n°3 de l'épisode 7. Rejoué seul : 74/0. Deux bancs à UML ne
se lancent pas en même temps. La complétion n'a **pas** été
touchée : le 7ᵉ journal y arrive parce qu'elle demande sa liste à `help` (12ᵉ application de la
règle d'unicité), et le placeholder du verbe s'appelle `<command-line>` — `<command>` désigne déjà
un verbe **du canal** dans cette grammaire, et la complétion aurait proposé les verbes du canal là
où on attend une commande d'invité. Deux assertions de l'épisode 17 ont été **retournées** plutôt
que supprimées (la connectivité n'est plus annoncée non tranchable ; le `SKIP` de `reaches` a une
autre raison), et une **erreur de banc** préexistante a été corrigée au passage : en `E2E=0`,
`verify-bench.sh` jouait `lab.mrv` — qui affirme `state s1 is off` — après avoir démarré ce switch
pour lire ses tables.

### 2026-08-12 — Épisode 19 : le skill qui conçoit un TP, et la grammaire qu'il ne doit pas réciter

**Ce qui manquait.** Tout l'outillage existe depuis l'épisode 18 : 43 verbes, 7 journaux, un
rapport à la demande, un exécuteur dans l'invité, un vérificateur déclaratif, un mode examen qui
archive. Personne n'avait écrit **comment on s'en sert** pour aller d'un énoncé à une note. C'est
le livrable que l'épisode 15 avait planifié en dernier, et pour la raison que D6 donne : on ne
conçoit pas une couche de verdict avant qu'un journal ait tourné.

**Livré.** `doc-src/lab-design-skill.md` — anglais, dans la documentation **livrée** parce qu'un
enseignant qui installe Marionnet doit l'avoir et que n'importe quel agent capable de lancer un
shell doit pouvoir le lire ; plus `.claude/skills/marionnet-lab-design/SKILL.md`, qui ne fait que
**renvoyer** à lui. Cinq directives, la carte des capacités **par intention**, le cycle de vie et
ses artefacts, ce qui est prouvable et par quoi, la hiérarchie de preuve en trois niveaux,
l'écriture du corrigé, onze pièges mesurés avec leur contre-règle, un TP complet, la procédure de
notation d'une session `--exam`, et une checklist de livraison.

**La décision de l'épisode.** L'invariant du dépôt interdit une seconde copie de la grammaire ;
un agent à qui l'on ne dit pas ce qui existe invente un verbe plausible. Tranché : **citer, et
faire vérifier la citation** — le skill nomme les 43 verbes et **aucune** arité, et le banc mesure
dans les deux sens (tout verbe publié est nommé ; aucune ligne de syntaxe n'est recopiée). Un verbe
neuf casse donc le banc au lieu de laisser la page vieillir.

**Deux corrections par la mesure.**

1. Le TP d'exemple devait porter un **routeur**. La seule image de routeur installée date de 2014
   et ne démarre pas : un exemple qu'on ne peut pas jouer n'est qu'un texte. Le nœud qui route est
   une machine à deux interfaces, et le skill dit pourquoi et ce que la substitution change.
2. La première version de l'assertion « aucune syntaxe recopiée » a **échoué à tort** : sept verbes
   sans argument ont pour syntaxe leur propre nom. Le défaut était dans le banc, pas dans le skill.

**Le discriminant.** Le corrigé du skill, joué contre la maquette conforme (hors examen) :
**13 PASS, 1 FAIL, 0 SKIP**, et le FAIL est exactement l'assertion que le § 7.4 réserve à la
session d'examen. Puis le banc applique au skill le **point 5 de sa propre checklist** : on coupe
le forwarding **en marche** par `exec`, on rejoue le **même** fichier, et **11 PASS, 3 FAIL** —
l'état bascule (`report … ip_forward`), l'expérience bascule (`reaches m1 m2`), la **trace** ne
bouge pas (`journal … contains ip_forward`). La distinction trace/état du § 4.2 du skill est donc
mesurée, sur la même machine et au même instant, et non raisonnée.

**Mesures.** `skill-bench.sh` neuf : **58 assertions, 0 échec** (41 sans UML). Aucun `.ml` touché.

**Reste.** L'épisode 20 : le guide de l'enseignant (anglais), un exemple par commande et des TP
complets fabriqués et notés, avec un § « concevoir et noter un TP avec un agent IA » qui met en
œuvre ce skill. Après quoi le chantier est clôturable.

---

### 2026-08-13 — épisode 20 : le routeur mesuré, et la question qu'il fallait poser

**Pourquoi maintenant.** Le § 6 portait, consignée la veille sur indication de l'auteur, la liste
**close** de ce que ce chantier n'avait **jamais pu jouer** faute d'une image de routeur qui
démarre. Le commit `79c25dd` (« the default kernel is now the most recent installed ») a levé
l'obstacle : un routeur créé aujourd'hui prend `6.12.95-i386` au lieu de la série 2014 « -ghost »,
et boote en quatre secondes. Cet épisode ne conçoit rien — il **joue**, et il corrige ce que jouer
a fait apparaître.

**Le défaut, et c'est le seul.** Trois scripts déposés dans l'invité bornaient leurs commandes
derrière une garde `type -p timeout` : le veilleur (ép. 16/18), le producteur de rapport (ép. 7) et
le collecteur (ép. 2). L'image de routeur **a** un `timeout` — celui de busybox 1.22, à l'ancienne
interface `-t SECS` — si bien que `timeout 180 /bin/bash -c …` y cherchait un programme nommé
« 180 ». Conséquence : **tout** `exec` rendait 127, **toutes** les sections du rapport et de la
collecte étaient vides. C'est mot pour mot la leçon de l'épisode 14 sur `tee` : on teste une
**capacité**, jamais un **moyen**. Les trois gardes jouent désormais la forme qu'elles vont
utiliser, et le repli du veilleur **nomme sa raison** dans le journal `exec`.

**Le discriminant est un nombre, mesuré dans les deux sens** (code précédent restauré par
`git stash`, binaire reconstruit, banc rejoué sur le même invité) : **17** sections
« can't execute » dans le rapport du routeur avant, **0** après. Un rapport présent et vide est le
pire cas pour une notation — il a l'air d'une réponse.

**Ce que le rejeu a rendu** (détail au § 4.19) : les quatre documents d'examen d'un routeur, ses
sept journaux, `report` et `exec`, les sept configurations Quagga **relues dans l'invité**, et le
TP d'exemple du skill réécrit avec un vrai composant `router` puis rejoué (13 PASS / 1 FAIL / 0 SKIP
sur la maquette conforme). Deux documents livrés ont été corrigés, qui affirmaient qu'aucune image
de routeur ne démarre.

**Deux découvertes de terrain.** Le **rapport à la demande** (ép. 16) écrit le fichier que
l'archivage du mode examen va chercher : sur une image SysV sans séquence d'arrêt, le mode examen
est donc complet au prix d'une commande — la limite du § 6 tombe. Et l'**historique** d'un invité
dépend d'un `HOME`, pas du fragment : le relais de guignol tourne avec `HOME=/`, un bash non-login
n'y lit aucun `bashrc`, alors qu'un étudiant — qui se **logue** — lit `/etc/profile.d/`. Rien à
corriger dans le dispositif ; c'est le banc qui simulait un cas qui n'existe pour personne.

**Deux défauts consignés, non corrigés** (§ 6) : `wait --ready` **ment au second démarrage** (le
hostfs n'est écrit qu'à la création du device simulé, qui survit au `poweroff` — mesuré sur machine
**et** routeur ; il touche le chemin de démarrage commun, donc il se tranche avec l'automate d'état
en tête) ; et le prompt de login a disparu du journal `terminal` d'une trixie depuis ce jour, ce que
le run de contrôle **avec le code précédent** reproduit à l'identique — donc pas cet épisode.

**Mesures.** Banc neuf `router-bench.sh` : **60 assertions, 0 échec** (10 sans UML). `exam-bench.sh`
**81 assertions, 1 échec** (celui ci-dessus, préexistant). Rejoués un par un : `skill-bench` 58/0,
`doc-bench` 66/0, `verify-bench` 84/0, `exec-bench` 60/0, `journal-bench` 171/0.

**Reste.** L'épisode **21** : le guide de l'enseignant (anglais), un exemple par commande et des TP
complets fabriqués et notés, avec un § « concevoir et noter un TP avec un agent IA ». Après quoi le
chantier est clôturable.

### 2026-08-13 — épisode 21 : le guide de l'enseignant, et l'exemple qui n'est pas une citation

**Pourquoi maintenant.** C'est le dernier épisode annoncé par le tableau du § 4, et le seul qui
manquait pour clore : les trois documents livrés jusqu'ici s'adressent à qui script
(`doc-src/scripting/README.md`), à qui n'a pas envie de scripter (`doc-src/exam-mode.md`) et à un
**agent** (`doc-src/lab-design-skill.md`). Personne n'avait écrit le **fil de l'enseignant**, de
son énoncé jusqu'à la note — ni, surtout, l'index promis « un exemple par commande ».

**La tension, et la décision.** L'index promis est exactement ce que le guide de scripting
**refuse** au nom de l'invariant du dépôt (§ 4 : « The command list is not in this guide »). Un
exemple, contrairement à un nom de verbe, **est** une syntaxe : la réponse de l'épisode 19 (citer
sans arité, faire vérifier la citation) ne suffisait donc pas. L'auteur a tranché : **les exemples
sont des gestes joués, pas des citations**. Le § 4 du guide est une session ordonnée, le banc la
rejoue ligne à ligne contre une Marionnet vivante, et la **couverture est mesurée par l'exécution
même** — une fonction `mrnctl` espionne note le verbe de chaque appel, l'ensemble obtenu est
comparé à celui que `help` publie, dans les deux sens. Un verbe neuf casse le banc ; une option
renommée fait échouer son exemple. Détail au § 4.20.

**Livré.** `doc-src/teacher-guide.md` (9 §, dont l'index des **43** verbes et le § « concevoir et
noter un TP avec un agent IA », écrit du côté de l'humain : ce qu'il doit **exiger** avant de
croire un agent) ; `doc-src/labs/session-7/` — un TP **réel** complet (C4 du corpus : routage,
filtrage, SNAT), avec ses deux clés, l'une pour une session vivante, l'autre pour une copie close ;
et le banc `teacher-bench.sh`. Trois renvois d'une ligne ont été ajoutés aux documents existants.

**Le discriminant** est le TP joué deux fois sur la même session : corrigé installé,
**14 PASS / 0 FAIL / 0 SKIP** ; puis forwarding coupé **en marche** par `exec`, la même clé rend
**12 PASS / 2 FAIL** — et les deux qui basculent sont l'**état** et l'**expérience**, la **trace**
passant encore. La hiérarchie des preuves du § 7.5, en deux lignes de sortie.

**Sept pièges neufs, tous mesurés** (§ 4.20) : le **quoting** d'un `rc-set` qui redirige (c'est le
shell de l'appelant qui lit la ligne en premier) ; les **noms de ports** qui diffèrent selon le
genre (`eth0…` pour une machine, `port0…` pour un composant `router`) ; `wait --ready` qui attend
pour rien quand le scénario n'écrit pas le marqueur ; les **titres des documents archivés qui sont
traduits** — un corrigé qui cherche `Report on` ne note rien sur une machine française ; le
**rapport d'arrêt qui n'est pas garanti** (trois machines éteintes peu après leur boot, une seule
avec son `report.md` — remède : le demander avant l'extinction, comme à l'épisode 20) ; et deux
pièges d'écriture de banc, dont un programme **awk cité par des apostrophes** qui contenait une
apostrophe dans un commentaire français, cassé **en silence**.

### 2026-08-14 — Épisode 22 : le mode examen refuse ce qui détruit sans archiver

**Le déclencheur est une question de l'auteur**, pas un défaut mesuré : « en `--exam`, pourquoi ne
pas interdire *Tout débrancher* et `mrnctl poweroff` ? — et cherche les autres oublis du même
genre ». La réponse au « pourquoi » tient en une phrase : **tout ce que le chantier archive est
accroché au seul arrêt gracieux**, si bien que chaque autre chemin d'extinction jette la copie que
l'enseignant est censé noter. L'audit en a trouvé **six**, dont trois que personne n'aurait
appelés dangereux : quitter en répondant « non » à la sauvegarde (qui **débranche** tout), le
`quit` du canal (qui détruit les processus et n'écrit rien) et `close --no-save` (qui, lui, arrête
proprement, mais jette l'archive avec le projet).

**Livré.** Une option, `--exam-allow-delete`, et cinq refus : le bouton « Tout débrancher »
insensible (avec son infobulle), les verbes `poweroff`/`poweroff-all` refusés par le canal, la
suppression refusée **pour ce qui a tourné seulement**, `--no-save` refusé, et `quit` refusé tant
qu'il resterait quelque chose à archiver ou à écrire. Un témoin dans le menu Options — coché,
grisé, absent hors examen — dit à l'étudiant pourquoi « Supprimer » ne lui propose plus rien. La
politique vit dans le **modèle** (`can_poweroff`, `can_destroy`) : la GUI et le canal la lisent,
aucun des deux ne la connaît. La grammaire de `help` n'a pas bougé — une restriction est une
**capacité**, pas un mot — mais `can` cesse de publier les actions verrouillées et `status`
publie `exam`, parce que les gestes de session (`poweroff-all`, `new`, `open`, `close`, `quit`)
n'ont pas de `can` où se dire.

**Ce que l'auteur a tranché contre la proposition initiale.** Le verrou de suppression devait être
une option qui **ajoute** un interdit (`--no-delete`) ; c'est l'inverse qui a été retenu —
l'interdit est le **défaut** en examen et l'option le **lève** — et surtout le critère n'est pas le
mode mais la **trace** : un composant jamais démarré reste supprimable, puisqu'il n'a rien produit.
D'où `has_left_traces`, à deux sources : le treeview des états (persisté, donc valable après
réouverture) et un drapeau de session (pour les genres sans état de disque, comme le switch).

**Le discriminant** est la même machine dans deux processus : bootée, arrêtée, sauvée, puis rouverte
par une Marionnet **neuve** en `--exam` — mémoire vide — où `del m1` est refusé quand même. C'est
le `.mar` qui répond. **Mesures** : deux bancs jetables, **43** et **19** assertions, 0 échec ;
GUI vérifiée à l'écran (bouton grisé, case grisée, sous-menu « Supprimer » vide) ; `dune build`
vert. Piège payé de deux runs : le serveur refuse **en silence** une socket dont le répertoire
parent est écrivable par le groupe.

### 2026-08-14 — Épisode 23 : sortir d'un projet, c'est l'enregistrer

**Le déclencheur, encore une question de l'auteur** : l'épisode 22 avait traité Quitter, mais
**Fermer**, **Nouveau** et **Ouvrir** demandaient toujours « voulez-vous enregistrer ? » et
acceptaient « Non » — la question dont la mauvaise réponse coûte le plus cher à un étudiant.

**Deux points de l'énoncé, mesurés avant d'être traités.** Le `(x)` de la fenêtre appelle la
**même** entrée que Projet→Quitter : il était déjà couvert, et cela se vérifie à l'écran.
L'hypothèse d'un drapeau `project_already_saved` qui mentirait après un archivage est **fausse**
(trois documents archivés, `saved` retombe à `false`) : la garde « déjà sauvé, donc rien à
demander » est donc gardée telle quelle.

**Le vrai défaut était en dessous**, et il aurait rendu la sauvegarde forcée décorative :
`shutdown_everything` **ordonnance** ses tâches et rend la main, or l'archivage est le **dernier**
geste d'un arrêt gracieux. Les quatre chemins écrivaient donc le `.mar` **pendant** l'extinction —
une course — et Quitter, qui tournait dans le thread GTK, enchaînait sur une coupure brutale.

**Livré** (tout dans `bin/gui/gui_menubar_MARIONNET.ml`) : une seule fonction de dialogue pour les
quatre gestes — en examen elle ne demande rien et répond « oui », hors examen elle demande **et
avertit** quand quelque chose a tourné (via `has_left_traces`, publié par l'ép. 22) — et une seule
fonction d'exécution qui met les trois temps dans l'ordre : arrêter, **attendre le task runner**,
puis sauver. L'attente interdisant le thread GTK, la réaction de Quitter **tourne désormais dans
un thread**, comme les trois autres.

**Discriminant** : ces gestes sont des **clics**, donc le banc pilote la GUI et **rouvre le `.mar`
dans un processus neuf**. Quitter avec une machine encore allumée laisse un fichier qui porte
*Rapport sur m1*, *Console of m1* et *Terminal of m1*. **Pièges payés** : `xdotool key` envoie au
focus (dangereux et infidèle — on clique dans le menu) ; un banc sous `set -e` **meurt en silence**
quand le geste testé fait disparaître la fenêtre ; les titres des dialogues sont **traduits**, donc
un motif anglais ne trouve rien et rend l'assertion creuse. Et un premier run à deux documents
n'était pas la course mais le défaut **déjà consigné** : une machine arrêtée trop tôt après son
boot n'écrit pas son rapport.

### 2026-08-15 — Épisode 24 : clôture

**La question posée** n'était pas « clôture ce chantier » mais « clos-le **s'il n'y a plus rien à
corriger** » — donc l'épisode commence par un audit du § 6, en lecture seule, et non par le rituel.

**Ce que l'audit a trouvé.** Deux entrées périmées, et une seule d'entre elles enseignait quelque
chose. La première, l'i18n de l'épisode 22, était simplement **faite depuis** (`5161c49`). La
seconde — « les titres des documents archivés sont traduits, et pas tous » — était le seul défaut
du § 6 que le chantier semblait s'être laissé à lui-même ; elle est tombée en trois mesures. Les
**quatre** titres passent par `s_` (`treeview_documents.ml:423,649,661,681`) ; `bin/po/fr.po` et le
catalogue installé du switch courant traduisent les **quatre** ; mais
`/usr/share/locale/fr/LC_MESSAGES/marionnet.mo` — le Marionnet **installé sur la machine**, daté du
**8 juillet 2023** — porte `Report on ` et **ni** `Console of ` **ni** `Terminal of `, qui sont nés
de ce chantier. Le mélange observé n'était donc pas une incohérence de catalogue mais le défaut
i18n **déjà consigné** au `docs/TODO.md` : un binaire lancé depuis l'arbre de développement lit le
catalogue d'un **autre** Marionnet. Leçon de méthode, et c'est la même qu'aux épisodes 14 et 20
(`tee`, `timeout`) : **ce qu'on croit mesurer sur le programme peut n'être qu'une propriété de la
machine** — ici, une installation de 2023 encore posée dans `/usr`.

**Ce qui restait ne relevait pas de la correction** : hors périmètre déclaré (hubs, flux
d'événements, rapport plus riche), renvoyé nommément à un autre chantier (`world_bridge`,
`kernel-rootfs`, l'installation), compromis assumés, ou défauts **du dépôt** qui se tranchent avec
l'automate d'état en tête. Le chantier est donc clos sans dette propre.

**Le rituel, ensuite** (MODE C du skill `chantier-long`), avec une addition qui n'y figure pas :
clore un chantier rend son document **archive**, et une archive ne se relit pas — les quatre
défauts durables qui survivent au chantier **sans lui appartenir** ont donc été reversés à la
TODOLIST transverse `docs/TODO.md`, où ils seront trouvés par qui n'aura jamais lu ce fichier. Le
reste est du ménage : § 8 neuf (résultat, limites, où sont partis les défauts), fiche mémoire
réduite à ses pièges transverses, entrée de `MEMORY.md` passée aux archives, et **retrait des
quelque 200 lignes** que le pointeur de `CLAUDE.md` faisait relire à chaque session — en préservant
les trois choses qui seraient mortes avec lui : le renvoi à cette archive, le piège
`preprocessor_deps` (dune ne voit pas à travers camlp4) et l'existence du skill
`marionnet-lab-design`.

**Aucun code touché** : cet épisode ne modifie que de la documentation et de la mémoire.
