# `marionnet-install.sh.bench/` — le banc du chemin **réseau** de l'installeur

> **Épisode 16** : ce banc a suivi son script de `useful-scripts/` vers `bin/scripts/`
> (le script est désormais **aussi** le chooser d'images `marionnet-get-images`), et il
> gagne **5 cas** pour ce second nom — **68 cas, 68 verts**. Piège payé au passage : `SUMS_TOOL` pointait deux
> niveaux au-dessus, il en faut **trois** — un chemin relatif sortant d'un répertoire est
> exactement ce qu'un déplacement casse, et le banc **sautait** au lieu de tourner.

L'épisode 6 du chantier `modernisation-installation-marionnet` a prouvé
`bin/scripts/marionnet-install.sh` **sur un miroir local**. Ce run exerce tout le
script *sauf* les deux lignes qui distinguent un miroir d'un serveur — et ces deux lignes
sont exactement ce qu'est un serveur de release :

| Fonction | Branche `dir` (prouvée ép. 6) | Branche `url` (ce banc) |
|---|---|---|
| `catalog_list`   | `ls -1` | `http_body` du répertoire, puis les noms lus dans les `href="…"` — **repli** depuis l'ép. 8 |
| `artifact_stream`| `cat`   | `http_body` de l'artefact |

Depuis l'**épisode 11b**, la branche `url` ne nomme plus de téléchargeur : elle passe par
`http_body` / `http_headers`, qui sont **`wget` ou `curl`** selon ce que porte la machine
(`wget` d'abord, parce que c'est avec lui que tout ce banc a été mesuré).

`www.marionnet.org` étant en panne, ce banc **dresse le serveur** au lieu de l'attendre :
un Apache dans un conteneur, un répertoire de release synthétique, et le script lancé
depuis un **second** conteneur qui ne contient que Debian et le script.

**Épisode 8** y a ajouté une troisième chose à mesurer, celle qui rend les deux autres
solides : un répertoire de release publie un **`SHA256SUMS`**, qui est **à la fois** le
catalogue et l'intégrité de ses artefacts ; le listing n'en est plus que le **repli**. Le
banc sert donc des répertoires **avec** et **sans** ce fichier, et rejoue sur les deux les
deux façons dont un Apache cesse de publier un listing (`index.html`, `Options -Indexes`) :
elles coulent le repli et ne touchent pas au catalogue publié.

**Épisode 9c** y ajoute la **troisième famille d'artefacts** : l'application elle-même
(`marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz`, produite par
`Makefile.d/release.binary.sh` depuis l'ép. 9a), que le client sait désormais **installer**
et non plus seulement cataloguer. Ce que le banc mesure là est le **choix** parmi les
applications publiées (arch, glibc, révision) et le **contrat** avec l'`install.sh` embarqué
— pas ce que fait un vrai Marionnet une fois installé : les tarballs de la famille portent un
`install.sh` **sonde** qui note comment il a été appelé. Le vrai est mesuré par
`Makefile.d/release.binary.sh.bench/`, sur un vrai tarball, en root ; il n'y a pas de raison
de le mesurer deux fois.

## Jouer le banc

```bash
bin/scripts/marionnet-install.sh.bench/run.sh          # le script du dépôt
bin/scripts/marionnet-install.sh.bench/run.sh /chemin/vers/un/autre/marionnet-install.sh
bin/scripts/marionnet-install.sh.bench/run.sh --distro ubuntu:26.04
bin/scripts/marionnet-install.sh.bench/run.sh --distro all   # les 4 boîtes (ép. 12)

# et, depuis l'épisode 27, contre le VRAI serveur au lieu des fixtures :
bin/scripts/marionnet-install.sh.bench/run.sh --from https://www.marionnet.org/download/apt
bin/scripts/marionnet-install.sh.bench/run.sh --distro all --from https://www.marionnet.org/download/apt
```

Conventions de `driven-sessions/README.md` : **`0` = PASS, `77` = SKIP, autre = FAIL**,
une ligne `PASS:`/`FAIL:` par cas, un décompte à la fin, et le banc nettoie derrière lui
(deux conteneurs, un réseau, **sept** volumes, un répertoire temporaire). Il **saute** (77) sans
Docker, sans démon Docker, ou si les images ne peuvent pas être construites.

Coût : quelques secondes après le premier run (qui tire `httpd:2.4` et l'image de la boîte).

## La boîte cliente est un paramètre (épisode 12)

`--distro <référence d'image>` choisit la distribution du **client** ; `--distro all` rejoue
le banc sur les quatre de la feuille de route — `debian:bookworm-slim`, `debian:trixie-slim`,
`ubuntu:24.04`, `ubuntu:26.04` — en ne rendant qu'un code de sortie (le pire des quatre).
Le défaut reste `debian:trixie-slim`. Images, conteneurs, réseau et volumes sont **suffixés**
par la boîte, de sorte que deux distributions ne se prennent jamais l'une pour l'autre.

Le serveur, lui, ne change pas : `httpd:2.4` sert les mêmes octets quel que soit celui qui
les télécharge.

**Ce qui a rendu ce portage presque gratuit est une décision de l'épisode 9c** : l'arch et
la glibc des artefacts synthétiques sont demandées au **conteneur client**, jamais à cet
hôte-ci. Toute la famille de cas `--binary` (l'élu, le supplanté, l'arch étrangère, la glibc
trop récente) suit donc la boîte d'elle-même. Résultat mesuré le 2026-08-31 : **63 verts sur
chacune des quatre**.

## Les trois décisions qui font que ce banc mesure quelque chose

1. **Apache, pas `python3 -m http.server`.** Le parsing de `catalog_list` vise un listing
   d'Apache — le script le dit lui-même. Servir un autre listing reviendrait à mesurer un
   analyseur contre une page que personne ne publiera jamais. `FancyIndexing` est activé
   **exprès** : c'est le listing difficile, celui qui ajoute les liens de tri
   `href="?C=N;O=D"` et un *Parent Directory* absolu. Mesuré : ils sont bien là, et le
   script les écarte.
2. **HTTP, pas HTTPS.** Un certificat auto-signé obligerait à passer
   `wget --no-check-certificate`, c'est-à-dire à mesurer une commande **différente** de
   celle qui tournera en production. La jambe https est une vérification d'une ligne
   contre le vrai site, le jour où il revient.
3. **Rien n'est monté dans le client** hormis le script lui-même : ni miroir, ni dépôt.
   Ce qui arrive dans son préfixe est passé par HTTP, ou n'est pas arrivé.

Le client est une boîte nue portant **seulement** `wget`, `tar`, `xz-utils` :
ce dont le script a besoin est ainsi **mesuré** au lieu d'être supposé — c'est la même
liste que devront porter le `.deb`, le RPM et l'image Docker.

**Depuis l'épisode 11b il y en a un second** (`Dockerfile.client.curl`), identique à une
différence près : `curl` **à la place de** `wget`. Une image portant les deux ne prouverait
rien, le script choisissant `wget` en premier. Et la boîte « ni l'un ni l'autre » n'est
que l'image de base brute, sans rien d'ajouté.

## Les artefacts sont synthétiques (et pourquoi)

Le répertoire de release fabriqué a la **forme** du vrai : les quatre tarballs *et* les
parasites qui les entourent sur le serveur (images et noyaux décompressés, `.conf`,
`.config`, un fichier caché, un répertoire `_variants`, un `README.txt`). Ce sont eux que
le catalogue doit écarter ; un banc bâti sur les seuls tarballs ne verrait pas un analyseur
qui les garde.

Les octets, eux, sont synthétiques (quelques centaines de kio) : le banc coûte une
seconde, pas les ~10 Gio de `website-repo/` — qui est **gitignoré**, donc ne peut pas être
la dépendance d'un banc versionné. Un run contre les vrais artefacts reste un **geste
manuel** :

```bash
# à jouer à la main, quand on veut mesurer le débit et non le mécanisme
docker run --rm -d --name mrn-real -p 8080:80 \
  -v "$PWD/website-repo:/usr/local/apache2/htdocs:ro" mrn-install-bench-httpd
bin/scripts/marionnet-install.sh --fetch-only \
  --from http://localhost:8080/download/marionnet-install.sh/1.0.x \
  --only guignol --prefix /tmp/mrn-real --yes
```

(Pour servir depuis l'hôte plutôt que depuis un conteneur, c'est
`--add-host=host.docker.internal:host-gateway` qu'il faut au client : sous Linux ce nom
n'existe pas tout seul.)

## Ce que chaque cas prouve, et sur quoi il devient rouge

Un banc qui passe des deux côtés ne prouve rien. Les mutants ci-dessous ont été joués
contre le banc ; chacun est une façon plausible de casser le script.

| Cas | Prouve | Rouge sur |
|---|---|---|
| 1a | le catalogue lu sur un listing Apache tient exactement les 4 artefacts | filtre `case` neutralisé |
| 1b | parasites **et** liens de tri `?C=…` écartés | idem (mesuré : les `?C=D;O=A` sont bien dans la page) |
| 1c | les **tailles** annoncées sur HTTP sont celles que le même répertoire donne lu en miroir | branche `url` d'`artifact_size` muette (l'état d'avant) |
| 1d | aucun artefact ne revient en taille inconnue (`?`) | idem |
| 1e | le plan annonce un vrai total, ni `0B` ni « size unknown » | idem |
| 1f | une taille **manquante** transforme le total en borne basse **annoncée** | l'ancien message (sous-comptage silencieux) |
| 2 | l'arbre posé, l'image et le noyau **octet pour octet** après HTTP | — |
| 2 bis | le **`mtime`** du backing file survit à l'extraction | `tar xmf` (`-m`) |
| 2 ter | le router arrive **en tant que lien**, et il résout | — |
| 2 quater | un router seul **avertit** que son lien serait cassé | avertissement supprimé |
| 3 | idempotence : un 2ᵉ run HTTP ne transfère rien | — |
| 4a | source **injoignable** ⇒ « cannot read the catalogue » | échec `wget` avalé |
| 4b | source qui **répond mais ne contient rien** ⇒ l'autre message | idem |
| 5a | `Options -Indexes` (403) ⇒ source **illisible**, pas source vide | idem |
| 5b | un `index.html` masquant le listing ⇒ catalogue vide **annoncé** | — |
| 6a | le catalogue lu dans le **`SHA256SUMS` publié**, sans avertissement de repli, un digest par artefact | `sums_read` muette (l'état d'avant l'ép. 8) |
| 6b | le **même `index.html`** ne masque plus rien | idem |
| 6c | **`Options -Indexes`** n'aveugle plus le client | idem |
| 6d | un artefact au digest publié est annoncé **vérifié**, et arrive octet pour octet | idem |
| 6e | un digest qui **ne correspond pas** arrête le run, et ce qui était extrait est **retiré** | comparaison neutralisée ; retrait supprimé |
| 6f | `--no-verify` installe quand même | — |
| 6g | le `SHA256SUMS` publié est relu par **`sha256sum -c`** lui-même, dans le client | — |
| 7a | `--fetch-only` **seul** ignore les `marionnet_*` d'une release qui en publie | l'application ajoutée à une option déjà publiée |
| 7b | le **choix** : plus grande révision compatible **retenue**, révision inférieure dite *superseded*, et chaque refus **nomme son critère** (arch / glibc) | critère de refus muet ou confondu |
| 7c | l'artefact est déplié **à côté**, puis s'installe par son propre `install.sh --prefix …`, **en root** | client devenu un second installeur ; préfixe non transmis |
| 7d | idempotence de l'application, par le **nom** de ce qui est en place | — |
| 7e | `--force`, `--no-sudoers`, `--no-config` **arrivent** à l'`install.sh` embarqué | passe-plats perdus |
| 7f | une release dont **aucune** application ne tourne ici est refusée en nommant **les deux** critères | refus global sans motif |
| 7g | un digest en écart sur l'application : rien n'est installé (rien à retirer — c'est le sens du dépli **à côté**) | vérification neutralisée |
| 7h | `--fetch-only --binary` en **un seul run** laisse l'application **et** l'image | modes exclusifs |

**Discriminance de la section 7, mesurée** : rejouée contre le script d'avant l'épisode 9c,
elle donne **16 échecs**. Trois de ses cas restent verts, et c'est normal — ce sont des
assertions d'**absence** (7a « `--fetch-only` ignore », « rien n'a été déplié », « rien n'a été
installé ») : sur un script qui ne connaît pas `--binary`, elles sont vraies pour la mauvaise
raison. Chacune est appariée à un cas **positif** qui, lui, devient rouge ; c'est le
même garde-fou que le préfixe vide du cas 6e.

Le cas 5a est aussi le **témoin de discriminance** du cas 1 : s'il passait lui aussi, c'est
que le cas 1 n'aurait jamais lu de listing.

**Deux faits d'implémentation payés par la mesure, et écrits ici pour qu'ils ne se
re-découvrent pas** : `mod_autoindex` **retire du listing ce qu'il ne peut pas `stat`**, donc
un lien symbolique cassé n'atteint jamais le catalogue — l'artefact « de taille inconnue » du
cas 1f est un fichier bien réel mais **illisible** (mode 000, donc 403). Et `wget --spider -S`
écrit les en-têtes sur **stderr**, une fois par saut de redirection : seul le **dernier**
`Content-Length` décrit le corps.

**Mesuré et assumé** : l'ordre d'extraction (machines avant routers) est **inobservable**
quand les deux tarballs sont pris — le banc reste vert avec les deux passes inversées. Ce
qui est observable, c'est le router pris **seul** : c'est le cas 2 quater.

**Deuxième inobservable, de la même famille (ép. 8)** : retirer le `wait` qui attend le
`sha256sum` du fifo laisse le banc **vert**. Le hacheur voit l'EOF dès que `tee` ferme le
tuyau et a fini d'écrire avant qu'on lise son résultat — sur 294 kio la fenêtre ne s'ouvre
pas. Le `wait` reste, parce que la course qu'il ferme se paierait sur un transfert de
1,5 Gio par un digest **vide**, donc par un **faux** écart, donc par la destruction d'un
artefact sain. Un invariant peut être une course : le banc dit alors qu'il ne sait pas la
voir, il ne dit pas qu'elle n'existe pas.

**Trois cas de préparation du banc valent aussi garde-fou** : la corruption du digest du
cas 6e est faite par `awk` et non par un `sed` de deux substitutions — la seconde
s'applique au résultat de la première et rend l'original (mesuré : le cas passait pour la
mauvaise raison) —, elle garde le champ à 64 chiffres hexadécimaux (un 65ᵉ caractère rend
la ligne illisible, et un digest non lu ne vérifie rien), et chaque cas de vérification
part d'un **préfixe vide** : un cas qui trouve l'artefact déjà posé ne mesure que
l'idempotence.

## Section 8 : la même chose avec `curl` (épisode 11b)

Dix cas, joués sur la seconde image. Toute la surface HTTP du script tient en **deux
verbes** — un **corps** (le catalogue, le listing quand il n'y en a pas, un artefact) et un
jeu d'**en-têtes** (la taille) —, et les cas les exercent tous les deux, sur les *mêmes*
répertoires servis que les sections précédentes : une différence entre les deux
téléchargeurs se voit alors dans le **résultat**, pas seulement dans la ligne de commande.
Six d'entre eux virent au rouge sur le script d'avant l'épisode (mesuré : `57 PASS / 6
FAIL`), les quatre autres passant faute d'être atteints — le run mourait avant, sur
`wget is required to fetch from…`.

Deux cas portent le vrai contenu de l'épisode :

- **le `-f`** : `kernels_linux-locked.tar.xz` est listé et répondu **403**. Sans `-f`,
  `curl` sort **0** et livre la page d'erreur à l'extracteur ; il ne resterait plus que le
  digest entre une page HTML et le disque. Le cas exige l'échec **et** l'absence de tout
  fichier posé sous ce nom.
- **l'absence de `-S`**, son symétrique : le `SHA256SUMS` manquant d'un répertoire publié
  avant l'épisode 8 est une condition **gérée** (on retombe sur le listing), pas un
  incident. `wget -q` n'en dit rien ; avec `-S`, `curl` écrivait `curl: (22) … 404` au
  milieu d'un run qui se passait bien (mesuré). Un cas vérifie qu'aucune ligne `curl:` ne
  subsiste dans la sortie.

## Où vont les images (épisode 28)

Quatre cas, à la fin du run, sur la question qui a ouvert l'épisode : *les trois canaux
écrivent-ils au même endroit ?* Les deux canaux **paquets** installent sous `/usr`, le
tarball sous `/usr/local`, et **les deux ont raison** — ce qui les réconcilie à l'exécution
est la cascade de configuration, dont le seul lecteur est le binaire. Jusqu'à l'épisode 28
ce script ne l'interrogeait pas : sa destination était la chaîne `/usr/local`, écrite en
dur, si bien que sur une machine où Marionnet venait d'un `.deb` ou d'un `.rpm` les images
atterrissaient **une arborescence à côté** de l'endroit où cette installation les cherche —
sans qu'aucune commande échoue.

Les cas montent un **stub** `marionnet.native` sous `/usr/local/bin` plutôt qu'une vraie
installation : ce qui est mesuré ici est la **lecture d'une réponse**, pas la capacité du
binaire à en produire une (cette moitié-là est mesurée par les bancs `.deb` et `.rpm`, avec
le paquet réel). Deux des quatre cas sont **discriminants** — rejoués sur le script d'avant
l'épisode : `70 PASS / 2 FAIL` — et les deux autres sont des **gardes de non-régression**,
vertes des deux côtés : le défaut `/usr/local` sur une machine sans installation, et la
souveraineté de `--prefix`.

## Restes ouverts que ce banc éclaire

- **Le cas 5b est un piège vivant, et le 6b est sa réponse** : le jour où le répertoire de
  release reçoit une page d'accueil, un catalogue **scrapé** devient vide sans que rien ne
  soit cassé côté publication. C'était l'argument du reste ouvert (b) de l'épisode 6 ; il
  est soldé depuis l'épisode 8 — `Makefile.d/release.sha256sums.sh` publie le fichier, et
  les deux cas se lisent l'un contre l'autre.
- **L'arch et la glibc sont demandées au conteneur client**, jamais à cet hôte : le choix se
  fait là où le script tourne, et un banc qui nommerait sa propre libc mesurerait la mauvaise
  machine dès que les deux diffèrent (ici : hôte `glibc2.39`, client trixie `glibc2.41`).
- Ce que le digest **ne** prouve **pas** : la provenance. `SHA256SUMS` voyage par la même
  route que les tarballs, donc un serveur compromis réécrit les deux. La signature est une
  question pour l'étape 1 du chantier, avec la clef du dépôt apt.
- Ce banc mesure **le mécanisme**, pas la configuration réelle de `www.marionnet.org` :
  l'autoindex peut y être désactivé ou habillé. La vérification contre le vrai site reste due.

## Le mode `--from URL` (épisode 27) — les fixtures et le vrai serveur ne mesurent pas la même chose

Point **(6)** de la feuille de route. `--from <URL>` laisse de côté l'Apache du banc et les
artefacts synthétiques, et pointe le script sur une **release publiée**. Les deux modes sont
**complémentaires, aucun ne remplace l'autre** :

- les **fixtures** tiennent ce qu'un vrai serveur ne peut pas montrer : un artefact **corrompu**,
  un `SHA256SUMS` **absent**, un `index.html` qui masque le listing, `Options -Indexes` ;
- le **mode distant** tient ce qu'elles ne savent pas imiter : l'Apache de production, **https**,
  le **lien stable** `download/apt`, et un catalogue de 1,7 Gio. Il joue donc la famille de cas
  qu'une release saine sait répondre — et **c'est là que la jambe https cesse d'être une
  vérification manuelle d'une ligne**.

Ce qui est **téléchargé** : l'image invitée (12 Mio) et l'application (7 Mio) — les deux seuls cas
qui écrivent des octets sur une machine (le `mtime` qu'UML vérifie, et `--binary`). Les grosses
images sont **listées**, jamais rapatriées.

### Le magasin de certificats est une dépendance du canal https

Mesuré à l'épisode 27, et **c'est une phrase que la doc INSTALL doit à son lecteur** : une image
Debian nue ne porte **aucune autorité de certification**, si bien que le catalogue https est
**illisible** — pendant exact de ce que le banc `.deb` mesure sur `apt`, de l'autre côté du canal.

Deux pièges à ne pas défaire dans ce cas :

1. **Le verdict se prend sur le catalogue qui revient, jamais sur le libellé d'un échec.** La
   première version lisait le message du script, n'y trouvait pas « certificate » et passait au
   **vert** sur une boîte qui venait de ne rien lire du tout — la famille « juger par autre chose
   que ce qu'on mesure » (ép. 19, 20b, 20c, 24). La boîte est donc interrogée **deux fois** : si
   ajouter `ca-certificates` répare, c'est bien lui qui manquait.
2. **Le libellé est mesuré ensuite, comme cas à part.** Avant l'épisode 27 le script annonçait
   `server down, no route, wrong URL?` à propos d'un serveur **debout** : il ne relayait pas le
   diagnostic de son téléchargeur. Il **sonde** désormais la même URL sans vérification de
   certificat avant de décider quoi accuser, et **nomme** `ca-certificates`.
