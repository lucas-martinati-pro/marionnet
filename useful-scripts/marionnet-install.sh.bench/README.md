# `marionnet-install.sh.bench/` — le banc du chemin **réseau** de l'installeur

L'épisode 6 du chantier `modernisation-installation-marionnet` a prouvé
`useful-scripts/marionnet-install.sh` **sur un miroir local**. Ce run exerce tout le
script *sauf* les deux lignes qui distinguent un miroir d'un serveur — et ces deux lignes
sont exactement ce qu'est un serveur de release :

| Fonction | Branche `dir` (prouvée ép. 6) | Branche `url` (ce banc) |
|---|---|---|
| `catalog_list`   | `ls -1` | `wget` du répertoire, puis les noms lus dans les `href="…"` |
| `artifact_stream`| `cat`   | `wget -q -O -` |

`www.marionnet.org` étant en panne, ce banc **dresse le serveur** au lieu de l'attendre :
un Apache dans un conteneur, un répertoire de release synthétique, et le script lancé
depuis un **second** conteneur qui ne contient que Debian et le script.

## Jouer le banc

```bash
useful-scripts/marionnet-install.sh.bench/run.sh          # le script du dépôt
useful-scripts/marionnet-install.sh.bench/run.sh /chemin/vers/un/autre/marionnet-install.sh
```

Conventions de `driven-sessions/README.md` : **`0` = PASS, `77` = SKIP, autre = FAIL**,
une ligne `PASS:`/`FAIL:` par cas, un décompte à la fin, et le banc nettoie derrière lui
(deux conteneurs, un réseau, un volume, un répertoire temporaire). Il **saute** (77) sans
Docker, sans démon Docker, ou si les images ne peuvent pas être construites.

Coût : quelques secondes après le premier run (qui tire `httpd:2.4` et `debian:trixie-slim`).

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

Le client est un `debian:trixie-slim` nu portant **seulement** `wget`, `tar`, `xz-utils` :
ce dont le script a besoin est ainsi **mesuré** au lieu d'être supposé — c'est la même
liste que devront porter le `.deb`, le RPM et l'image Docker.

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
useful-scripts/marionnet-install.sh --fetch-only \
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
| 2 | l'arbre posé, l'image et le noyau **octet pour octet** après HTTP | — |
| 2 bis | le **`mtime`** du backing file survit à l'extraction | `tar xmf` (`-m`) |
| 2 ter | le router arrive **en tant que lien**, et il résout | — |
| 2 quater | un router seul **avertit** que son lien serait cassé | avertissement supprimé |
| 3 | idempotence : un 2ᵉ run HTTP ne transfère rien | — |
| 4a | source **injoignable** ⇒ « cannot read the catalogue » | échec `wget` avalé |
| 4b | source qui **répond mais ne contient rien** ⇒ l'autre message | idem |
| 5a | `Options -Indexes` (403) ⇒ source **illisible**, pas source vide | idem |
| 5b | un `index.html` masquant le listing ⇒ catalogue vide **annoncé** | — |

Le cas 5a est aussi le **témoin de discriminance** du cas 1 : s'il passait lui aussi, c'est
que le cas 1 n'aurait jamais lu de listing.

**Mesuré et assumé** : l'ordre d'extraction (machines avant routers) est **inobservable**
quand les deux tarballs sont pris — le banc reste vert avec les deux passes inversées. Ce
qui est observable, c'est le router pris **seul** : c'est le cas 2 quater.

## Restes ouverts que ce banc éclaire

- **`artifact_size` ne sait rien sur HTTP** (`url) : ;;`), donc `--list` affiche une taille
  vide et le plan annonce « 0 B to transfer ». Un `wget --spider -S` donnerait le
  `Content-Length`. Cosmétique, mais c'est le chiffre que lit l'utilisateur avant d'accepter.
- **Le cas 5b est un piège vivant** : le jour où le répertoire de release reçoit une page
  d'accueil, le catalogue devient vide sans que rien ne soit cassé côté publication. C'est
  l'argument le plus concret en faveur du reste ouvert (b) de l'épisode 6 — **publier un
  fichier d'index à côté des artefacts** plutôt que dépendre de `mod_autoindex`.
- Ce banc mesure **le mécanisme**, pas la configuration réelle de `www.marionnet.org` :
  l'autoindex peut y être désactivé ou habillé. La vérification contre le vrai site reste due.
