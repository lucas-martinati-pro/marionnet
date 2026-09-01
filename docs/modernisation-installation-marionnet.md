# Chantier : modernisation de l'installation et de la diffusion de Marionnet

**Slug (commits, mémoire, grep)** : `modernisation-installation-marionnet`
**Objectif** : remplacer l'installeur historique `useful-scripts/marionnet_from_scratch`
(mort de fait depuis ~2022) par une diffusion moderne et rationalisée : script
nouvelle génération, paquets (.deb + RPM), conteneur Docker officiel, artefacts
précompilés servis par marionnet.org — le tout **outillé et scriptable** de bout en bout.
**Nature** : chantier **parent** (étude + coordination + socle commun) destiné à
**essaimer des chantiers enfants** par canal (§ 4), sur le modèle
`finitions-port-dune` → `marionnet-camlp4-ppx`.

## 1. Contexte et décisions de cadrage (2026-07-18)

Le script `marionnet_from_scratch` a été l'installeur universel du projet jusqu'en ~2022 :
sur Debian-like il allait au bout ; ailleurs il servait de guide technique à transposer.
Sa mort n'est pas venue de lui : les couples kernel/image qu'il télécharge
(`linux-3.2.64-ghost` + wheezy/guignol) ont cessé de booter sur les hôtes modernes
(stub SKAS0 cassé, cf. `docs/retro-compatibilite-kernels-images.md`). Depuis, deux
chantiers ont produit les remplaçants — UML 6.12.95 (+ variante `-i386`) et Debian 13
trixie (`docs/kernel-rootfs-refresh.md`) — mais ces artefacts sont **encore uniquement
locaux** : le serveur sert toujours les couples morts (constat § 2.3). Par ailleurs
l'architecture d'installation a changé : **plus de daemon root** (chantier
`marionnet-daemon-elimination` → `Tap_provider` + règle sudoers scoped posée par
`bin/scripts/marionnet-sudoers.sh`), i18n et install passés sous dune.

Décisions actées avec Jean (grill, session du 2026-07-18) :

- **Publics : tous** — étudiant sur portable, salle TP/admin, distros non-Debian,
  curieux « démo en 5 min ». Conséquence : **multi-canaux**, chaque canal ayant un
  public privilégié (matrice § 3.2).
- **Binaires précompilés : oui**, à condition d'une charge de release **entièrement
  outillée** (un `make release-…` construit et dépose tout ; pas de manipulation manuelle).
- **Docker = canal officiel**, adossé au sous-projet MarioNUM
  `~/WORKING/MARIONUM/MARIOLINE/marioline.next/docker_images/ubuntu-vnc-xfce-g3-marionnet/`
  (fork accetto/ubuntu-vnc-xfce-g3 ; le Dockerfile 20-04 consomme déjà une variante
  `marionnet_from_scratch.20-04.sh` + `opam.INSTALL.sh` — l'image actuelle embarque
  l'ANCIEN Marionnet à daemon root, cf. C4 de `docs/bug-critique-crash-host.md`).
- **VM VirtualBox/QEMU : canal abandonné** (précédent 2017, `MARIONNET-VM-virtualbox.README`,
  exports .ova) — le conteneur couvre le besoin « prêt à l'emploi ».
- **Paquets : .deb servis par un dépôt apt maison sur marionnet.org** (signé GPG) **+
  filière RPM ravivée** (`RPMS/` existe : specs marionnet-common/fs-machines/fs-routers/
  kernels + Makefile). **Pas** de visée d'inclusion dans Debian/Ubuntu officiels.
- **Structure : parent + enfants** (§ 4).
- Jean est **administrateur de marionnet.org** : dépôt libre de tout artefact utile
  (kernels, images invitées, binaires, paquets), sous licence libre.

## 2. Autopsie de `marionnet_from_scratch` (v0.98.3, 2025-02-14, 1699 lignes)

### 2.1 Inventaire fonctionnel

Dans l'ordre d'exécution :

1. **Infra** : `set -e` + `trap ERR`, parsing d'options long→court maison (getopt-like),
   répertoire de travail temporaire `TWDIR` avec **reprise** (`-c DIR` rejoue en sautant
   les étapes du journal `already_done`), `launch_and_log` (exécution journalisée avec
   **progression en % estimée par poids** de log, relance `--as-root` via script
   temporaire), wget aliasé `--no-check-certificate`, gestion proxy (`-Y`).
2. **Debian-like** : détection (`dpkg -L bash`/`apt`), construction de la liste de
   paquets requis (compile + runtime), cas spéciaux par version d'Ubuntu (camlp4 vs
   camlp4-extra, `libc6-i386` vs `libc6:i386` ≥ 22.04, overlay-scrollbar ≥ 16, vde2
   packagé si ≥ 2.2.1), `apt install --no-install-recommends` après confirmation.
3. **Sources Marionnet** : tarball « latest » de la série depuis Launchpad ou le mirror
   maison ; trunk via `bzr branch lp:marionnet`.
4. **Compilation/installation** : `sed` du prefix dans `CONFIGME`, `opam init -y && make
   configure switch` (switch **4.13.1** + `OPAM_PACKAGES` : camlp4, dune, lablgtk3,
   lablgtk3-extras, lablgtk3-sourceview3…), `make rebuild`, `make install`, symlink
   `marionnet` → `marionnet.native`.
5. **vde2** : si `vde_switch` absent, téléchargement (sourceforge 2.3.2 de 2013, ou
   mirror) + `./configure && make && make install`.
6. **graphviz** : idem si `dot` absent (2.26.3 de 2010 !).
7. **Kernels + filesystems** : scrape du listing HTML de
   `marionnet.org/download/marionnet_from_scratch/$SERIES/`, `wget -O - | tar xzf -`
   dans `$PREFIX/share/marionnet/` (`kernels_*.tar.gz`, `filesystems_*.tar.gz`,
   tiny vs large sélectionnables ; option `-O/--download-only`).
8. **`marionnet.conf`** : détection des lecteurs PDF/HTML/éditeur installés + layout
   clavier depuis `$LANG`, `sed` dans le conf, copie vers `/etc/marionnet/`.
9. **Daemon** : génération d'un init-script SysV `marionnet-daemon`, liens `rc[2-5S].d`,
   `systemctl enable` si systemd, création `/dev/net/tun`, lancement.
10. **Fixes distro** : X `-nolisten tcp` (gdm/lightdm/xinit, série 0.90.x seulement) ;
    `update-rc.d`/`insserv` ; alias `UBUNTU_MENUPROXY=0` (Ubuntu ≥ 11) ; gsettings
    `Gtk/ButtonImages` (Ubuntu ≥ 20) ; backport PPA vde2 (Ubuntu 12.04) ; symlink
    `port-helper` s'il est hors PATH ; avertissement PATH `$PREFIX/bin` ; migration des
    locales `/usr/local/share/locale` → `/usr/share/locale` (heuristique) ; avertissement
    `libc6-i386` sur x86_64.

### 2.2 Verdicts bloc par bloc

| Bloc | Verdict | Motif / remplaçant moderne |
|---|---|---|
| Infra bash (reprise `-c`, `launch_and_log` pondéré) | **Réinventé, à re-concevoir** | Qualité réelle mais ad hoc ; un script v2 neuf devra trancher **si et comment exploiter bashbricks** (vendored dans le dépôt, règle repo pour tout nouveau script) |
| Liste deps Debian | **Principe valide, liste à rafraîchir** | Vérifiée sur Kubuntu 24.04 : tout est packagé (§ 2.4) ; les branches Ubuntu 10–16 sont mortes |
| `libc6:i386` | **Toujours requis** (conditionnel) | Nécessaire pour exécuter `linux-6.12.95-i386` (rétro-compat wheezy/guignol) sur hôte x86_64 |
| Compilation vde2 from source | **Mort** | `vde2` packagé partout (Debian trixie 2.3.2+r586-11, Ubuntu noble -10) |
| Compilation graphviz from source | **Mort** | `graphviz` packagé partout |
| Chaîne opam (`make configure switch` / `rebuild` / `install`) | **Vivante mais à reléguer** | Squelette toujours compatible avec le port dune (cibles `switch`, `rebuild`, `install`=`install-final-as-root` existent) ; ~30-60 min et fragile → voie « from source » de repli, plus la voie par défaut |
| Téléchargement kernels/filesystems | **Principe à conserver, contenu mort** | Le `wget \| tar xzf` préserve les MTIME (impératif de partage de projets) ; mais le serveur sert les couples morts (§ 2.3) |
| `marionnet.conf` (readers, layout, `/etc/marionnet`) | **À conserver** | Toujours pertinent |
| Daemon SysV/systemd | **Mort** | Daemon éliminé ; remplacé par `marionnet-sudoers.sh install` (déjà appelé par `make install-final-as-root`) + `Tap_provider` |
| X `-nolisten tcp` | **Mort** | Limité à 0.90.x dans le script ; le pont X11 est `bin/x.ml` (:6000) |
| `UBUNTU_MENUPROXY=0` | **Mort** | Réglage GTK2/Unity ; GUI en GTK3 depuis le port lablgtk3 |
| gsettings ButtonImages (Ubuntu ≥ 20) | **À retester** | Peut rester pertinent (GTK3 masque les images de boutons) ; à vérifier sur GNOME/KDE actuels |
| Backport vde2 12.04, overlay-scrollbar | **Morts** | Distros disparues |
| Symlink `port-helper` | **D'actualité** | `port-helper` (uml-utilities) est toujours utilisé par les consoles xterm UML |
| Migration locales `/usr/local` | **Mort** | Réglé par dune-site (ép. 6 `finitions-port-dune` : localeprefix en tête de cascade) |
| Avertissement PATH | **À conserver** | Toujours utile pour prefix `/usr/local` |
| bzr trunk | **Mort** | Conversion bzr→git (2026-07) ; `git clone` (Launchpad, bascule VCS par défaut encore à faire) |

### 2.3 État du serveur marionnet.org (constaté le 2026-07-18)

`https://www.marionnet.org/download/marionnet_from_scratch/` :

- séries `0.90.x/` (2018), `0.94.x/` (2018), `0.98.x/` (2025-02-12), `trunk/` (2018),
  `stuff/` (2014) + vieux artefacts 2010 à la racine (lenny, mandriva, pinocchio,
  kernel 2.6.18-ghost) ;
- `0.98.x/` sert : `kernels_linux-3.2.64-ghost.tar.gz` (2016),
  `filesystems_machine-debian-wheezy.tar.gz` (2017), `filesystems_guignol.tar.gz` (2017)
  → **les couples morts sur hôte ≥ ~5.15** ;
- `0.98.x/mirror/` : `graphviz-2.26.3` (2010), `lablgtk-2.14.2` (2010), `vde2-2.3.2`
  (2013), `marionnet-0.98.3.tar.gz` (2023, **pré-port-dune**).

**Rien de ce que Marionnet 2026 requiert n'y est.** Les artefacts modernes existent
localement : kernels `linux-6.12.95{,-i386}` + configs, image
`machine-debian-trixie-*` (+ `.conf` `INIT_SYSTEM=systemd`/`GHOSTIFICATION=netns`),
`.conf` wheezy/guignol patchés (`SUPPORTED_KERNELS` + `/-i386$/`, ép. 2 retro-compat —
patchs notés « à reporter côté serveur ») et hook
`bin/filesystems/machine-debian-wheezy-08367.relay`. L'outillage de pose locale existe :
`uml/pupisto.debian/Makefile.d/install.last-built-couple.sh` (restauration MTIME comprise).

### 2.4 Dépendances : état 2026 (vérifié sur Kubuntu 24.04, cohérent Debian trixie)

| Dépendance | apt 24.04 | Note |
|---|---|---|
| vde2 | 2.3.2+r586-10 | runtime obligatoire |
| uml-utilities | 20070815.4-1build2 | `port-helper`, `uml_mconsole`, `tunctl` |
| graphviz | 2.42.2 | `dot` (onglet topologie) |
| liblablgtk3-ocaml-dev | 3.1.4 | build système (voie opam : lablgtk3 opam) |
| camlp4 | **4.14+1** (noble) / **5.3+1** (trixie) | voir question ouverte § 6 |
| opam | 2.1.5 | voie from source |
| glade, libgtksourceview-3.0-dev, rlfe, fonts-noto, bridge-utils, xterm… | présents | liste complète du script encore packagée |

**Découverte notable** : camlp4 est packagé par Debian/Ubuntu en versions suivant les
compilateurs récents (4.14, 5.3). Le « gel OCaml 4.13.1 » du projet est un artefact du
**dépôt opam** (dernière `camlp4` opam compatible) — une piste « toolchain système »
(ocaml + camlp4 + lablgtk3 apt, sans opam) mérite instruction, avec prudence : rien ne
garantit que le code compile en OCaml ≥ 4.14/5.x, et le chantier `marionnet-camlp4-ppx`
attaque le problème par l'autre bout (sortir de camlp4).

### 2.4 bis Source de vérité des dépendances : le `Makefile` (depuis le 2026-07-27)

**Décision** : la liste des dépendances n'est plus dérivée du script mourant
`marionnet_from_scratch` ni redécouverte par canal. Le `Makefile` (§ *dependencies*) la porte,
scindée en deux variables, et **chaque canal de diffusion la dérive** :

| Variable | Contenu | Consommateurs |
|---|---|---|
| `REQUIRED_PACKAGES_BUILD` | `opam pkg-config build-essential libgtk-3-dev libgtksourceview-3.0-dev gettext glade` | `make dependencies` ; `Build-Depends` du `.deb` ; image de build Docker |
| `REQUIRED_PACKAGES_RUNTIME` | `vde2 graphviz uml-utilities xterm iproute2 sudo x11-xserver-utils xauth jq socat dnsmasq-base xz-utils libgtksourceview-3.0-1` (`bridge-utils` **retiré** le 2026-08-23 ; les **2 derniers ajoutés le 2026-08-30**, épisode 9b) | **`Depends` du `.deb`** ; `Requires` du RPM ; couche runtime Docker ; script v2 `marionnet-install.sh` |
| `REQUIRED_PACKAGES_RUNTIME_I386` | `libc6:i386` | `Recommends` (ou `Suggests`) du `.deb` — voir ci-dessous |
| `REQUIRED_PACKAGES` | union des deux | cible historique `apt-dependencies` |
| `OPAM_PACKAGES` | `dune dune-site camlp4 camlp-streams inotify lablgtk3 lablgtk3-sourceview3 conf-gtksourceview3` **`yojson base64`** (`lablgtk3-extras` **retiré** le 2026-08-31, épisode 21) | `make opam-dependencies` ; `Build-Depends` du `.deb` ; `BuildRequires` du RPM ; image de **build** Docker ; essai « toolchain système » (ép. 3) |

**Ajout du 2026-08-09 — `yojson` et `base64`**, posés par l'épisode 2 du chantier
`migration-marshal-to-text` (codec JSON de `lib/STRUCTURES/xforest.ml` ; le repli base64 est ce
qui rend le fichier de projet réellement lisible par un autre outil). Ils sont **déjà** dans
`OPAM_PACKAGES`, donc `make dependencies` les couvre sur la voie opam. Ce qui reste à faire
relève de **chaque canal**, quand il sera construit : les répercuter là où la voie **système**
remplace opam. Équivalents Debian **vérifiés** : `libyojson-ocaml-dev`, `libbase64-ocaml-dev` ;
les équivalents RPM restent à vérifier le moment venu.

⚠️ Ce sont des dépendances **de build uniquement** — vérifié : `ldd` sur `marionnet.exe` ne montre
aucune bibliothèque `yojson` ni `base64`, les bibliothèques OCaml étant liées statiquement. Rien
à ajouter au `Depends` du `.deb`, au `Requires` du RPM ni à la couche runtime Docker.

**Ajout du 2026-08-23 (épisode 1) — `jq`, `socat`, `dnsmasq-base` : la source de vérité avait
décroché du code.** Trois chantiers postérieurs au 2026-07-27 ont fait appeler par l'hôte des
binaires que `REQUIRED_PACKAGES_RUNTIME` ne déclarait pas ; le § 2.4 ter les avait consignés comme
« contraintes entrantes » pour les futurs paquets, mais la variable dont tous les canaux vont
**dériver** leur `Depends` ne les portait pas — donc `make dependencies` laissait une machine
fraîche incapable de démarrer un bridge ou d'utiliser un client du canal. Corrigé à la source :

| Paquet | Site d'appel mesuré | Chantier d'origine |
|---|---|---|
| `jq` | `bashbricks/bashbricks.sh` (module `Json_*`, **fichier installé**, sourcé par `bin/scripts/marionnet-{nat,lan}bridge.sh`) ; `bin/scripts/marionnet-check.sh` et `marionnet-verify.sh` (alias `mrn-check`, `mrn-verify`), qui **refusent de démarrer** sans lui (`command -v jq \|\| die`) | `modernisation-world-bridge`, `pilotage-par-script` |
| `socat` | `bin/scripts/marionnet-ctl.sh` (alias `marionnet-ctl`, `mrnctl`) (`socat - UNIX-CONNECT:<socket>`, garde `command -v socat \|\| die`) | `pilotage-par-script` |
| `dnsmasq-base` | `bin/scripts/marionnet-dnsmasq.sh` (service DHCP/DNS lié au seul bridge d'un `nat_bridge`, et RA IPv6 via `--enable-ra`) | `modernisation-world-bridge` (ép. 10c, 11) |

⚠️ **`dnsmasq-base`, jamais `dnsmasq`** : le second ajoute un service système qui dispute le
port 53 à l'hôte, alors que le premier fournit le binaire seul (`dpkg -L dnsmasq-base` →
`/usr/sbin/dnsmasq`). Et ce n'est pas une dépendance facultative : le service DHCP est actif **par
défaut** sur un NAT bridge, sans aucun repli quand le binaire manque (décision de l'ép. 10c.2).

**Retrait du 2026-08-23 (épisode 2) — `bridge-utils`.** Relevé à l'épisode 1, tranché à l'épisode 2 :
`brctl` n'a plus **aucun site d'appel**. L'existence d'un bridge se lit dans sysfs
(`bin/global_options.ml`), le LAN bridge se construit à l'`ip link` seul
(`bin/scripts/marionnet-lanbridge.sh`), et le dernier appelant — `useful-scripts/prepare_bridge.sh`
(2007 : `brctl`, `ifconfig`, `mii-tool`, trois outils morts) — a été **retiré de l'arbre versionné**
par le ménage du même épisode. `iproute2`, déjà requis, couvre tout ce qu'on lui demandait. La
raison du retrait est écrite dans le `Makefile` lui-même, à la place du paquet : une liste de
dépendances ne dit rien sur ce qu'elle ne contient pas, et c'est précisément ce qui fait
re-déclarer un paquet mort au canal suivant.

Cibles : `apt-build-dependencies`, `apt-runtime-dependencies` (les deux appelées par
`apt-dependencies`, donc par `make dependencies`) et l'opt-in `apt-runtime-dependencies-i386`.

**Implication pour l'outillage release (§ 3.3)** : le champ `Depends` du paquet ne doit **jamais**
être écrit à la main dans `debian/control` — le générer depuis `$(REQUIRED_PACKAGES_RUNTIME)`
(p. ex. via un `debian/control.in` + substitution, ou `${misc:Depends}` complété par le
Makefile). Même règle pour le `Requires` du RPM et le `apt install` du script v2 : une seule
liste, un seul endroit à mettre à jour quand le code appelle un nouveau binaire.

**Justification, paquet par paquet** (chaque entrée est adossée à un site d'appel dans le code,
commenté dans le `Makefile`) : `vde2` → `vde_switch`/`slirpvde` (vérifiés au démarrage par
`bin/marionnet.ml`) + `wirefilter` ; `graphviz` → `dot` (vérifié au démarrage) ;
`uml-utilities` → **`uml_mconsole`** (`simulation_level.ml#gracefully_terminate`, `serial.ml`) —
et **non** `uml_switch`, qui n'est plus utilisé nulle part ; `xterm` → terminal par défaut ;
`iproute2` → `ip` (`tap_provider.ml`) ; `sudo` → privilèges scopés post-daemon-elimination ;
`x11-xserver-utils` → `xhost` ; `xauth` → MIT-MAGIC-COOKIE-1 lu au
lancement (`bin/x.ml`) et transmis aux invités ; `jq`, `socat`, `dnsmasq-base` → ajout du
2026-08-23, table ci-dessus.

**Écartés** par rapport au tableau § 2.4 et au script : `bridge-utils` (retiré le 2026-08-23, voir
ci-dessus — `brctl` n'a plus d'appelant), (`socat` figurait ici jusqu'au 2026-08-23,
comme dépendance **invité** : il l'est toujours, mais il est devenu aussi une dépendance **hôte**,
d'où sa remontée dans la liste) : `rlwrap`/`rlfe`/`ledit` (confort du terminal de gestion, `simulation_level.ml:542` : absence sans
conséquence → au plus `Suggests`), `fonts-noto` (cosmétique → au plus `Recommends`),
`liblablgtk3-ocaml-dev`/`camlp4` système/`bzr`/`libtool` (voie opam), les paquets
`Essential: yes` (coreutils, tar, grep, libc-bin).

**Cas `libc6:i386`** : nécessaire seulement pour exécuter les noyaux UML `SUBARCH=i386` des vieux
couples (chantier `marionnet-retro-compat-kernels-images`), et son installation implique
`dpkg --add-architecture i386` sur l'hôte. D'où la cible opt-in, hors de `make dependencies` ;
côté `.deb`, il relève au mieux d'un `Recommends`, à trancher quand le canal sera construit.


**Ajout du 2026-08-30 (épisode 9b) — `xz-utils` et `libgtksourceview-3.0-1` : la liste était
écrite par des gens qui compilaient.** Les deux trous ne pouvaient apparaître qu'en donnant le
tarball binaire à une machine qui n'a **que** cette liste, ce que fait le banc
`Makefile.d/release.binary.sh.bench/`. `xz-utils` parce que tout artefact publié est un
`.tar.xz` et que `xz` n'est pas `Essential` (contrairement à `tar`) ;
`libgtksourceview-3.0-1` parce que les bibliothèques GTK arrivaient jusque-là comme
dépendances de `REQUIRED_PACKAGES_BUILD` — un poste qui **exécute** n'a pas ces paquets de
build. Un seul paquet suffit pour les 13 bibliothèques `NEEDED` du binaire, et son nom est
stable de bookworm à trixie/noble, là où `libgtk-3-0` a pris un `t64` en chemin.

### 2.4 ter Ce que l'installation ne pose pas : les clients du canal (constat 2026-08-12)

**Constat mesuré** (`grep -rn 'useful-scripts' Makefile Makefile.d/*.mk` : aucun résultat) :
**aucun** client du canal de contrôle n'est installé, par aucune cible. `install-final-as-root`
fait `dune install --prefix` puis copie `$(SHARE_DIR)/scripts/*` dans `$(PREFIX_INSTALL)/bin/` —
ce sont les scripts déclarés par `bin/dune`, qui en 2026-08 ne comptaient que les scripts
**déposés dans les invités**, pas les clients de `useful-scripts/`. Les outils n'étaient donc
utilisables que **depuis un clone du dépôt**. *(Les deux encadrés ci-dessous lèvent ce constat :
le mirroring n'a pas changé, c'est le contenu de `bin/scripts/` qui a changé.)*

C'est un défaut, et pas seulement une commodité manquante, pour trois raisons vérifiables :

1. **La documentation utilisateur les appelle par leur nom nu.** `doc-src/scripting/README.md`
   écrit `mrnctl help`, `mrn-check lab.mrn`, `mrn-verify lab.mrv` — donc en supposant le `$PATH`.
   Idem `doc-src/exam-mode.md` et les exemples versionnés.
2. **Les scripts eux-mêmes le supposent.** `find_ctl` (dans `mrn-check` comme dans `mrn-verify`)
   cherche `marionnet-ctl` **à côté du script**, puis dans `$PATH` ; et le commentaire d'en-tête
   des deux justifie l'absence de `bashbricks` par une phrase qui est aujourd'hui **fausse** :
   « this script is meant to sit in `$(PREFIX)/bin` next to `marionnet-ctl` ». Le raisonnement
   reste bon (une bibliothèque sourcée par chemin relatif casserait une fois installée) ; c'est
   l'installation qui manque.
3. **Un binaire installé sans ses clients n'est pas pilotable par script**, ce qui est exactement
   ce que les chantiers `marionnet-pilotage-par-script` et `journalisation-profonde` ont construit.

**À installer** (nommer chacun : `bin/dune` nomme ses fichiers installés **un par un**, et un
fichier non nommé n'est pas installé — c'est ainsi que la complétion reste hors de
`$(PREFIX)/bin/`) :

| Fichier | Destination | Remarque |
|---|---|---|
| `bin/scripts/marionnet-ctl.sh` | `$(PREFIX)/bin/` | le client |
| `bin/scripts/marionnet-ctl`, `mrnctl`, `mrn-control` | `$(PREFIX)/bin/` | **liens** vers le précédent — dont le nom court historique |
| `bin/scripts/marionnet-check.sh` | `$(PREFIX)/bin/` | vérificateur d'un `.mrn` |
| `bin/scripts/marionnet-check`, `mrn-check`, `mrnck`, `mrn2sh` | `$(PREFIX)/bin/` | **liens** vers le précédent ; `mrn2sh` : le **nom implique `--to-bash`** |
| `bin/scripts/marionnet-verify.sh` | `$(PREFIX)/bin/` | vérificateur déclaratif d'un labo qui tourne (`.mrv`) |
| `bin/scripts/marionnet-verify`, `mrn-verify` | `$(PREFIX)/bin/` | **liens** vers le précédent |
| `bin/scripts/marionnet-completion.bash` | `/usr/share/bash-completion/completions/` (ou `$(PREFIX)/share/…`) | dessert les **12** noms ci-dessus (`.sh` compris) |

> **RÉSOLU (partiellement) le 2026-08-21 — par une stanza `install` de dune.** Tous les
> exécutables du tableau ci-dessus, **plus `marionnet-cleanup`** (et ses liens), sont désormais
> installés par **dune** : la stanza les pose dans `share/marionnet/scripts/`, que le `Makefile`
> **mirroir déjà** dans `$(PREFIX)/bin/` en les rendant exécutables (liens durs pour
> `install-final-as-root`, symboliques pour `install-for-testing`) — d'où **aucune ligne de
> `Makefile` à ajouter**. La voie « stanza dune » tranche donc l'alternative laissée ouverte plus bas.
>
> **Mise à jour du 2026-08-23 — la stanza a changé de fichier, pas de comportement.** Le chantier
> `move-and-rename-useful-scripts-to-bin-scripts` a ramené les cinq fichiers complémentaires du
> binaire dans `bin/scripts/` (chacun en `.sh` réel entouré de liens qui gardent **tous** les noms
> d'usage) : `useful-scripts/dune` s'est vidé, puis **a été supprimé** — il n'y a plus aucune
> déclaration de build dans `useful-scripts/`, et c'est `bin/dune` qui installe, **vers la même
> destination**. Rien à refaire ici : seuls les **chemins** de ce paragraphe et du tableau
> changent. Deux noms neufs sont apparus au passage (`mrnck`, `mrn-control`), déclarés par la
> complétion.
> Ce qui a forcé la décision : Marionnet **nomme** `marionnet-cleanup` à l'écran depuis l'ép. 6 de
> `marionnet-todo-transverse`, et **le lance lui-même** depuis les deux boutons de cet
> avertissement (2026-08-21) — un programme qui dit à l'utilisateur de lancer une commande doit
> lui laisser cette commande sur le `PATH`.
> **RÉSOLU le 2026-08-31 (épisode 14) pour la DOCUMENTATION** — même mécanisme, autre
> fichier : `doc-src/dune`, une stanza `install` en section `share_root` qui pose les **26**
> fichiers écrits pour qui n'a pas le dépôt sous `$(PREFIX)/share/doc/marionnet/`, arborescence
> conservée. Détail et mesures : § « Épisode 14 » ci-dessous.
>
> **Restent à faire ici** : la **complétion bash** (`bin/scripts/marionnet-completion.bash` n'est
> pas une commande et ne va pas dans `bin/` — cf. la ligne du tableau ; le motif de son absence
> vit désormais dans un commentaire de `bin/dune`, là où on chercherait la ligne manquante), la
> déclaration de **`socat`** et
> **`jq`** comme dépendances **hôte** dans les paquets (`Depends`/`Requires`/image Docker), et le
> même travail pour la **documentation d'usage** (complément 2026-08-13 ci-dessous).
> Note sur les liens : dune installe `mrnctl` et `mrn2sh` en **copies**, ce qui préserve le
> comportement (les deux scripts lisent `${0##*/}`, jamais l'inode), mais ne dispense pas les
> paquets de poser de vrais liens s'ils préfèrent.

⚠️ **Les liens ne sont pas décoratifs** : `mrn2sh` est `mrn-check` sous un autre nom, et le script
lit `$0` pour en déduire son mode (`mrn2sh` ⇒ `--to-bash` implicite) ; `mrnctl` est le nom court
de `marionnet-ctl`. Une installation qui les **copie sous un autre nom**, ou qui n'en pose qu'un
seul, change le comportement. Poser des liens (symboliques ou durs), jamais renommer.

Pour la complétion, un seul fichier dessert les **12** noms (trois `complete -F` en fin de
fichier) : l'installer une fois et, si la distribution l'exige, créer des liens par nom de commande.

**Deux dépendances runtime en découlent**, et elles corrigent le § 2.4 bis :

- **`socat` redevient une dépendance HÔTE** s'il faut installer les clients : `marionnet-ctl` en a
  besoin pour parler à la socket unix (`command -v socat || die`, `marionnet-ctl:130`). Le § 2.4
  bis l'avait écarté au motif — exact — qu'il est une dépendance **invité** ; il l'est **aussi**
  côté hôte dès que le canal est utilisé depuis la ligne de commande. À trancher au moment du
  paquet : `Depends` si les clients sont dans le paquet principal, `Recommends` s'ils partent dans
  un paquet séparé (p. ex. `marionnet-cli`).
- **`jq`** est requis par `mrn-check` et `mrn-verify` (et optionnel pour `marionnet-ctl` :
  `--query`, `--pretty`). Même arbitrage.

**Complément 2026-08-13 (venu de l'épisode 21 de `journalisation-profonde`) : la documentation
utilisateur n'est, elle non plus, installée par aucune cible.** Même mesure, même résultat
(`grep -rn 'doc-src' Makefile Makefile.d/*.mk` : aucun résultat). Ce n'était qu'un manque tant que
`doc-src/` contenait des sources historiques (`documentation.texi`) ; ça n'en est plus un depuis
que ce dossier porte **la** documentation d'usage, écrite pour être lue par un enseignant qui
**n'a pas** le dépôt :

| Fichier | Pour qui |
|---|---|
| `doc-src/teacher-guide.md` | l'enseignant : de l'énoncé à la note, un exemple par commande |
| `doc-src/scripting/README.md` + `doc-src/scripting/examples/` | qui pilote le canal (les exemples sont **exécutables**) |
| `doc-src/exam-mode.md` | l'enseignant qui ne script pas |
| `doc-src/lab-design-skill.md` | un **agent IA** à qui l'on délègue la conception d'un TP — le guide de l'enseignant dit « lis ce fichier et suis-le », donc il faut qu'il **existe** sur la machine |
| `doc-src/labs/session-7/` | un TP complet **rejouable** (scripts + clés) : il sert de modèle, donc il s'installe comme les exemples |
| `doc-src/project-format-v3.md` | le format `.mar` |

Destination naturelle : `$(PREFIX)/share/doc/marionnet/`, en gardant l'arborescence (les documents
se **citent par chemin relatif** entre eux — c'est le mécanisme qui remplace la recopie de la
grammaire). Deux points à trancher au paquet : les scripts de `labs/` et de `scripting/examples/`
sont **exécutables** et doivent le rester (`doc` en lecture seule les rendrait inutilisables sans
copie préalable), et le guide de l'enseignant cite `doc-src/…` — à relire une fois le chemin
d'installation choisi, ou à laisser tel quel en le disant.

**Voie d'implémentation** (à trancher à l'épisode qui construira l'install) : soit une stanza
`install` de dune (les clients deviennent des `(files …)` d'une section `bin`, ce qui les fait
suivre `dune install --prefix` et donc tous les canaux), soit une copie explicite dans
`install-final-as-root`, sur le modèle de la boucle existante des scripts invités. La première a
la préférence de principe (un seul mécanisme d'installation), sous réserve que dune sache poser
des **liens** — sinon, les deux liens se font à la main dans la cible.

> Contrainte entrante enregistrée le 2026-08-12, au sortir de l'épisode 17 de
> `journalisation-profonde` (`docs/journalisation-profonde.md` § 4.16), qui a ajouté le cinquième
> exécutable de la famille.

**Complément 2026-08-20 (venu de l'épisode 6 de `marionnet-todo-transverse`) : `marionnet-cleanup`
non plus, et il est désormais nommé À L'ÉCRAN.** Même mesure, même résultat. Ce n'était jusqu'ici
qu'un outil de dépannage réservé à qui a le dépôt ; depuis cet épisode, Marionnet **affiche au
démarrage** un dialogue qui dit combien de répertoires de run les sessions passées ont laissés et
renvoie explicitement à la commande `marionnet-cleanup --purge-dirs` — le seul geste proposé à
l'utilisateur, et le seul autorisé à retirer ces répertoires (Marionnet n'en retire aucun de
lui-même, par décision : ils contiennent la copie de travail non enregistrée). Un utilisateur qui a
installé Marionnet lit donc, aujourd'hui, le nom d'une commande qu'il n'a pas. Le script rejoint
la liste ci-dessus ; à la différence des clients du canal, il ne demande **ni `socat` ni `jq`**
(bash + coreutils + `/proc`) et n'appelle aucun lien de compatibilité.

### 2.5 Satellites de `useful-scripts/` (strates historiques)

> **Mise à jour du 2026-08-23 (épisode 2) : les strates ci-dessous ne sont plus dans l'arbre.**
> Le ménage de `useful-scripts/` — étape 5 du plan § 5, « archivage explicite des strates
> historiques » — a été fait : elles vivent maintenant dans `useful-scripts/BACKUP/`, **hors git**
> (le `.gitignore` du dépôt couvre `useful-scripts/*` depuis toujours ; ce que git suit ici n'a
> jamais été le contenu du répertoire, mais la courte liste des fichiers qu'on a choisi de suivre).
> Il restait alors **10 fichiers suivis** : `dune`, `marionnet_from_scratch` (gardé comme pièce à
> conviction de l'autopsie § 2), `make_marionnet_bytecode_revno`, `marionnet-completion.bash` et
> les 6 exécutables installés. **Depuis le 2026-08-23 (fin du chantier
> `move-and-rename-useful-scripts-to-bin-scripts`), il n'en reste que 2** :
> `make_marionnet_bytecode_revno` et `marionnet_from_scratch` — les cinq fichiers complémentaires
> du binaire (avec leurs liens) sont partis dans `bin/scripts/`, et `useful-scripts/dune`, devenu
> vide, a été supprimé. Quatre fichiers **versionnés** avaient été retirés à cette occasion :
> `prepare_bridge.sh` (conséquence : `bridge-utils` quitte les dépendances, § 2.4 bis),
> `which_ocamlbricks`, `marionnet_from_scratch.up-to-0.94.sh` et
> `marionnet_from_scratch_weights_of_log`.
> ⚠️ Les entrées ci-dessous restent **utiles au chantier** (`…_fedora_Sami.sh` = référence du canal
> RPM, `install_on_site` = germe de l'outillage release, `required_debian_packages.sh` /
> `search_runtime_dependencies.sh` = idée de dérivation des deps) : les chercher désormais dans
> `useful-scripts/BACKUP/`, et **ne pas compter sur git pour les restituer** — seuls les quatre
> fichiers ci-dessus ont un passé versionné.

- `marionnet_from_scratch.{VDI,2018.02.04,orig,NEW,up-to-0.94.sh,*.backup}` : versions
  antérieures (0.94.x : OCaml 3.11/3.12, lablgtk2, ocamlbricks séparé, compilés from
  source). **Valeur d'archive uniquement.** La `.VDI` servait à fabriquer la VM (canal abandonné).
- `marionnet_from_scratch_fedora_Sami.sh` : précédent yum/RPM (2013 : vde svn,
  ocamlbricks bzr, unité systemd daemon) — **référence utile au canal RPM**.
- `marionnet_from_scratch.install_on_site` : dépôt du script + tarballs trunk sur le
  serveur via ssh — germe de l'**outillage release** (§ 3.3).
- `0003-Hack-marionnet-from-scratch-to-download-only.patch` (Lucas Nussbaum) : intégré
  depuis (`-O`).
- `required_debian_packages.sh` / `search_runtime_dependencies.sh` : dérivation
  semi-automatique de la liste des deps runtime — idée à reprendre dans l'outillage.
- `uninstall_marionnet.sh`, `marionnet_from_scratch.BUG`, `HOWTO_make_a_release_*` :
  périphériques ; le HOWTO 2024 documente la release Launchpad (bzr, à migrer git).

## 3. Architecture cible proposée

### 3.1 Serveur : des artefacts versionnés et outillés

Principe : **marionnet.org devient un dépôt d'artefacts binaires à jour**, alimenté
exclusivement par des cibles make/scripts (aucun dépôt manuel). Arborescence cible
(à affiner à l'épisode 1) — les contenus versionnés sont **par série** (décision : le
port dune ouvre la série **1.0.x**, § 6), les dépôts apt/rpm sont transverses (leur
versionnement est interne aux paquets) :

```
download/
├── marionnet-install.sh/       # le script v2 ET ce qu'il télécharge, par série
│   └── 1.0.x/                  # (les anciennes URLs marionnet_from_scratch restent
│       │                       #  servies avec un message de redirection)
│       ├── SHA256SUMS           # LE CATALOGUE (et l'intégrité) — cf. note ép. 8
│       ├── kernels_linux-6.12.95.tar.gz
│       ├── kernels_linux-6.12.95-i386.tar.gz
│       ├── machine-debian-trixie-<SUM>{,.conf,.relay,_variants/}
│       ├── filesystems_machine-debian-trixie-<SUM>.tar.gz
│       ├── machine-debian-wheezy-08367{,.conf,.relay,_variants/}
│       ├── filesystems_machine-debian-wheezy-08367.tar.gz
│       ├── filesystems_{machine,router}-guignol-18474.tar.gz  (.conf patchés inclus)
│       └── marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz   # l'application (ép. 9a)
├── 1.0.x/
│   └── src/                    # tarballs sources du port dune (git archive)
├── apt/                        # dépôt apt signé (canal .deb)
└── rpm/                        # canal RPM
```

Note (2026-08-23) : les couples ne vivent pas dans un `couples/` séparé, comme le dessinait
la première version de ce §, mais **à côté du script qui les télécharge**, dans
`download/marionnet-install.sh/<série>/` — arborescence déjà en place sur le serveur, et que
`make filesystem.prepare-snapshot-to-publish` alimente. Chaque image y est publiée **sous ses
deux formes** : décompressée (ce que sert un `wget` direct) et empaquetée
`filesystems_<image>.tar.gz` (ce que consomme l'installeur, entrées préfixées `filesystems/`).

Bénéfice immédiat : les tarballs de couples régénérés incluent les `.conf` patchés
(fin du « patch à rejouer si l'image est retéléchargée » des ép. 2-3 retro-compat).

Note (2026-08-23, épisode 6) : **une source d'artefacts est un mot, pas un mode**. Le script
v2 prend un `--from` qui est soit l'URL ci-dessus, soit un **répertoire local** jouant le rôle
de miroir de cette URL. Ce n'est pas un artifice de test : c'est ce qui permet de construire et
de prouver toute la mécanique **pendant que le serveur est en panne**, et c'est aussi ce dont a
besoin une salle de TP sans accès Internet (miroir sur clé USB ou sur un partage local). Seules
deux fonctions du script connaissent la différence — `catalog_list` et `artifact_stream` — tout
l'aval est commun, de sorte qu'un run sur miroir exerce le **vrai** chemin et non une variante.
Le répertoire de travail employé ici est `website-repo/download/marionnet-install.sh/1.0.x/`
(ignoré par git : plusieurs gibioctets d'artefacts publiés).

Note (2026-08-30, épisode 8) : **le catalogue d'une release est le fichier `SHA256SUMS`**, pas
le listing du serveur. Une ligne `sha256sum` porte un **nom** *et* une **empreinte** : un seul
fichier publié répond donc aux deux questions que pose l'installeur (« que contient cette
release ? », « cet artefact est-il arrivé entier ? »), là où un index séparé et un fichier de
sommes seraient deux vérités capables de diverger. Il est écrit par
`Makefile.d/release.sha256sums.sh`, que les deux `*.prepare-to-publish` appellent d'eux-mêmes
après avoir posé un tarball. **Conséquence à ne pas oublier en publiant à la main** : un
artefact déposé sans passer par là est **invisible** de l'installeur, et une ligne laissée
derrière un artefact supprimé annonce ce qui n'est plus là (d'où le retrait des lignes
orphelines). La lecture du **listing** subsiste, mais seulement comme **repli** pour un
répertoire publié avant ce fichier.

Note (2026-08-30, épisode 9a) : **le binaire précompilé n'a pas de répertoire à lui.** La
première version de ce § lui dessinait un `download/<série>/binaries/` ; il vit finalement
**dans le même répertoire de release** que les images et les noyaux, donc dans le **même**
`SHA256SUMS`. Motif : le catalogue dit *ce qu'une release contient*, et une release dont
l'application est ailleurs oblige un consommateur à connaître deux emplacements et à faire
confiance à deux fichiers de sommes capables de diverger. Le prix de ce choix est explicite :
`bin/scripts/marionnet-install.sh` ne récupère que `filesystems_*` et `kernels_*`, donc une
ligne `marionnet_*` est **cataloguée et ignorée** au fetch — sans erreur (mesuré : le filtre du
catalogue est un `case` qui laisse tomber ce qu'il ne connaît pas). C'est un reste, pas un
défaut.

### 3.2 Matrice canaux × publics

| Canal | Public privilégié | Contenu | Chantier |
|---|---|---|---|
| **Script v2** | non-Debian (guide), admins, repli universel | deps apt si Debian-like + binaire ou compilation opam + couples + conf | enfant `…-par-script` |
| **.deb + dépôt apt** | étudiant portable, salle TP Debian-like | `marionnet` (binaire+ressources), `marionnet-kernels-*`, `marionnet-fs-*` (découpage à décider) | enfant `…-par-paquet-deb` |
| **RPM** | Fedora/openSUSE | ~~specs `RPMS/` modernisées~~ → **fait autrement, épisode 17** : specs **générés** par `release.rpm.sh`, 3 paquets + **2 dépendances tierces** (`vde2`, `uml-utilities`) qu'aucune distribution RPM ne porte ; `RPMS/` supprimé | enfant `…-par-paquet-rpm` |
| **Docker** | démo rapide, environnements verrouillés | image VNC/noVNC XFCE (MarioNUM g3) avec Marionnet moderne sans daemon | enfant `…-par-docker` |
| **From source** | experts, distros exotiques, dev | opam switch 4.13.1 (chaîne actuelle documentée) | parent (doc INSTALL) |

Tous les canaux consomment les **mêmes couples** (`download/marionnet-install.sh/<série>/`) et la **même
config** — factorisation au parent.

### 3.3 Outillage release commun (parent)

- `make release-couples` : tar.gz des couples installés/buildés (MTIME préservés, `.conf`
  patchés inclus) + dépôt ssh sur le serveur (germe : `install.last-built-couple.sh` +
  `marionnet_from_scratch.install_on_site`).
  **Mise à jour du 2026-08-23 : ses deux moitiés locales existent** — `make
  filesystem.prepare-snapshot-to-publish` (épisode 3) pour les images, `make
  kernel.prepare-to-publish KERNEL=<nom>` (épisode 5) pour les noyaux. Ce qui reste à
  écrire n'est plus la fabrication mais le **dépôt sur le serveur** (rsync/ssh), qui
  appartient à l'étape 1 du § 5.
- `make release-binary` : build propre + `dune install --prefix` dans un staging +
  tarball binaire relocatable (question § 6) — base des canaux script v2 / .deb / RPM / Docker.
- `make release-src` : `git archive` de la série.
- Signature GPG des artefacts et des index (dépôt apt notamment).

## 4. Chantiers enfants candidats (essaimage au fil des épisodes)

1. `modernisation-installation-marionnet-par-script` — script v2 (périmètre : Debian-like
   bout-en-bout + mode guide ; réutilise deps § 2.4, binaire ou opam, couples, conf).
2. `modernisation-installation-marionnet-par-paquet-deb` — empaquetage .deb + dépôt apt
   signé sur marionnet.org.
3. `modernisation-installation-marionnet-par-paquet-rpm` — ~~specs `RPMS/` ravivées~~ :
   **entamé à l'épisode 17**, et sur une autre base — les specs de 2009 étaient du code mort
   (aucune cible du `Makefile` ne les appelait) et leur découpage était déjà réfuté. Restent le
   dépôt `createrepo` et l'image de build EL9.
4. `modernisation-installation-marionnet-par-docker` — image MarioNUM g3 passée au
   Marionnet moderne (sans daemon, base 24.04+), publication (registre à décider).

Le **parent garde** : l'autopsie (§ 2, close), la remise à niveau du serveur, l'outillage
release commun (§ 3.3), la doc INSTALL from-source, la cohérence inter-canaux et la
clôture des enfants.

## 5. Plan d'épisodes (parent) — ordre acté le 2026-07-19

1. **Remise à niveau du serveur** : arborescence `download/` cible (§ 3.1, série
   `1.0.x/`) + `make release-couples` + dépôt des couples modernes (6.12.95,
   6.12.95-i386, trixie, wheezy/guignol re-tarrés avec `.conf`/`.relay` patchés).
   Prérequis de tout canal. — **La FABRICATION locale des artefacts est faite** (images :
   épisode 3 ; noyaux : épisode 5) ; reste l'arborescence servie et le **dépôt** sur le
   serveur.
2. **Outillage binaire** : `make release-binary`, staging `dune install --prefix` +
   tarball, test sur machine vierge (conteneur jetable). La relocatabilité est acquise
   (§ 6, point réglé) : le tarball embarque un `marionnet.conf` adapté si besoin.
   — **La FABRICATION est faite (épisode 9a)**, le test sur machine vierge aussi
   (épisode 9b), et **le consommateur sait l'installer** (épisode 9c) : ce point 2 est
   **soldé**, à ceci près que l'artefact n'est pas encore déposé sur un serveur (point 1).
3. **Essai toolchain système** (borné à une session, § 6) : tentative de build avec
   ocaml 4.14 + camlp4 4.14+1 + liblablgtk3-ocaml-dev d'apt, sans opam. Succès → le
   .deb devient source-buildable et le script v2 se simplifie ; échec → documenté, on
   en reste à opam (la levée du gel reste au chantier `marionnet-camlp4-ppx`).
4. **Essaimage des enfants, dans l'ordre** : `…-par-script` (déverrouille aussi le
   Dockerfile MarioNUM) → `…-par-paquet-deb` → `…-par-docker` → `…-par-paquet-rpm`.
5. **Doc INSTALL** moderne (from source + renvois canaux) ; ~~nettoyage des vestiges
   `useful-scripts/` (archivage explicite des strates historiques)~~ **fait le 2026-08-23**
   (épisode 2, § 2.5) ; clôture.

## 5 bis. Feuille de route révisée (2026-08-31) — elle prime sur l'ordre du § 5

L'ordre de 2026-07-19 supposait que l'étape 1 (le serveur) vienne d'abord. Elle est
**bloquée par l'extérieur** depuis, et les épisodes 3 à 10 ont montré qu'on pouvait tout
mesurer sans elle. L'ordre effectif est donc celui-ci, et il reste **local jusqu'à (5)** :

1. **Finir le local** — les deux restes de la consommation : la **complétion bash** (§ 2.4
   ter) et le **repli `curl`** (reste de l'ép. 6). C'est l'épisode 11, ci-dessous.
2. **Les quatre boîtes** — `marionnet-install.sh` (binaire + images + noyaux) éprouvé sur
   **Debian 12, Debian 13, Ubuntu 24.04, Ubuntu 26.04**. Ce qui change d'une distribution à
   l'autre, c'est la **glibc** (donc le choix de l'artefact, lu dans son nom), les **noms de
   paquets**, et le répertoire où `bash-completion` regarde. **C'est l'épisode 12,
   ci-dessous** : les trois écarts sont mesurés, et seul le premier en est un.
3. **Combien de `.deb`** — le découpage de l'application en paquets. **C'est l'épisode 13,
   ci-dessous** : la décision du § 6 tient, mais devient **quatre** paquets (`marionnet`,
   `marionnet-kernels`, `marionnet-kernels-i386`, `marionnet-fs-guignol`), le `Depends:` se
   **dérive** de la donnée générée à l'épisode 10, et le paquet routeur du précédent RPM
   disparaît (un artefact routeur n'est plus qu'un lien).
3 bis. **`doc-src/` s'installe** — étape **révélée par l'épisode 13** : les guides d'usage
   ne sont posés par **aucun** canal (§ 2.4 ter), et cela ne se répare pas dans le `.deb`
   mais dans une stanza `install` de dune, d'où **tous** les canaux le reçoivent. **C'est
   l'épisode 14, ci-dessous.**
4. **Les `.deb` sur les quatre boîtes** — en deux temps : **15a** les fabriquer
   (`Makefile.d/release.deb.sh`, cinquième publieur) et les contrôler localement, **15b** les
   installer sur les quatre boîtes, dépôt apt à plat compris. **Les deux sont faits** :
   `Makefile.d/release.apt.sh` écrit `Packages`/`Release`, et
   `Makefile.d/release.deb.sh.bench/` joue `apt install` sur les quatre boîtes.
5. **`upload.www.marionnet.org.sh`** — le dépôt d'un répertoire de release
   (`website-repo/download/marionnet-install.sh/1.0.x/`) sur le serveur. C'est ce qui reste
   de l'étape 1 du § 5.
6. **Rejeu de (2) et (4) contre le vrai serveur** — la jambe https comprise.

**Hors de cet ordre, sur demande** : l'épisode 16 (`marionnet-get-images`), l'**épisode 17**
(le canal RPM) et l'**épisode 20** (la boîte de compilation — la « matrice de compilation »
devenue un **plancher**, `debian:12`, appliquant enfin à l'application la règle que l'ép. 19
avait tirée des paquets tiers). Ce dernier était censé venir après Docker ; il a été joué avant, et il a
déplacé une hypothèse du § 3.2 : les dépendances d'exécution que le canal Debian obtient
gratuitement (`vde2`, `uml-utilities`) **n'existent dans aucun dépôt RPM**, si bien que le
canal doit les empaqueter lui-même. Il reste au canal RPM son dépôt `createrepo` et, pour
servir Rocky 9 / Leap 15.6, une image de build à la glibc plus ancienne.

La **doc INSTALL** (point 5 du § 5) devient le **tout dernier** épisode du chantier : elle
devra parler des `.deb` et des `.rpm`, donc elle ne peut pas être écrite avant eux.

## 6. Décisions sur les questions ouvertes (grill du 2026-07-19)

- **Relocatabilité du binaire — RÉGLÉ (factuel)** : `bin/configuration.ml` +
  `bin/initialization.ml:245-254` — `MARIONNET_PREFIX`, `MARIONNET_FILESYSTEMS_PATH`,
  `MARIONNET_KERNELS_PATH`, `MARIONNET_LOCALEPREFIX` sont lus de la cascade
  (`$prefix/share/marionnet/marionnet.conf` → `$prefix/etc/…` → `/etc/marionnet/…` →
  `~/.marionnet/…` → environnement), `Meta.prefix` n'étant que le défaut compilé.
  Un binaire compilé prefix `/usr/local` se redirige par un `marionnet.conf` posé par
  le paquet/script. Aucun patch de relocation.
- **Séries/versions : nouvelle série `1.0.x`** — la rupture est réelle (dune, daemon
  éliminé, couples 6.12/trixie, git) ; s'accorde avec le tag `AAA` et la bascule VCS
  git par défaut sur Launchpad encore en attente (mémoire `conversion-bzr-git`) —
  actions à raccrocher à l'épisode 1.
- **Granularité .deb : app + kernels + petites images en .deb, grosses images à part** —
  le dépôt apt porte `marionnet` (binaire + ressources + conf + sudoers),
  `marionnet-kernels` (~20 Mo) et les petites images (guignol, 16 Mo) ; les grosses
  (wheezy 560 Mo, trixie ~5 Go) restent dans `download/marionnet-install.sh/1.0.x/`, récupérées par
  un outil dédié (commande type `marionnet-get-images`, proposée en postinst).
  **REJUGÉ ET PRÉCISÉ le 2026-08-31 (épisode 13, ci-dessous)** : la décision tient, mais le
  découpage devient **quatre** paquets — les deux noyaux se séparent (seul l'i386 tire
  `libc6-i386`), machine et routeur d'une même image se réunissent (le routeur n'est plus
  qu'un lien), il n'y a **pas** de paquet `-doc`, et le postinst **nomme** la règle sudoers
  au lieu de l'accorder. Les chiffres qui l'établissent sont dans cet épisode.
- **Toolchain système : essai borné à une session** (épisode 3 ci-dessus).
- **Registre Docker : Docker Hub** — standard de facto (`docker pull`), découvrabilité,
  outillage ci-builder du fork accetto déjà orienté Hub.
- **Nom du script v2 : `marionnet-install.sh`** — « from scratch » mentirait dès lors
  que la voie par défaut installe des binaires ; les anciennes URLs
  `marionnet_from_scratch` restent servies avec un message de redirection.

## Journal d'avancement

- **2026-07-18 — épisode 0 (étude + officialisation)** : autopsie complète de
  `marionnet_from_scratch` v0.98.3 (§ 2 : inventaire, verdicts bloc par bloc, état du
  serveur constaté par consultation web, dépendances vérifiées apt 24.04, satellites) ;
  décisions de cadrage actées au grill (§ 1 : tous publics, binaires si outillés, Docker
  officiel adossé à MarioNUM g3, VM abandonnée, .deb dépôt maison + RPM, structure
  parent/enfants) ; architecture cible et plan d'épisodes proposés (§ 3-5) ; questions
  ouvertes listées (§ 6). Officialisation chantier-long (doc + fiche mémoire + pointeur
  CLAUDE.md). Aucun code touché.
- **2026-07-19 — épisode 0 (suite) : questions ouvertes tranchées** (grill) : § 6
  converti en décisions — relocatabilité réglée factuellement (cascade
  `configuration.ml`, aucun patch) ; série `1.0.x` ; .deb = app + kernels + petites
  images, grosses images via outil de téléchargement ; essai toolchain système borné à
  une session (nouvel épisode 3) ; Docker Hub ; script v2 renommé `marionnet-install.sh`.
  Ordre d'essaimage acté : script → deb → docker → rpm (§ 5 réécrit, arbo § 3.1 par série).
- **2026-07-27 — les dépendances ont une source de vérité unique** (`Makefile`, § 2.4 bis) :
  `REQUIRED_PACKAGES` scindée en `REQUIRED_PACKAGES_BUILD` / `REQUIRED_PACKAGES_RUNTIME`
  (+ `REQUIRED_PACKAGES_RUNTIME_I386` opt-in), avec les cibles `apt-build-dependencies` /
  `apt-runtime-dependencies` ; `make dependencies` installe désormais de quoi **compiler ET
  exécuter**. Motif immédiat : Marionnet signalait au lancement des dépendances absentes
  (`vde_switch`, `slirpvde`, `dot`) qu'aucune cible n'installait. Effet pour ce chantier : le
  `Depends` du futur `.deb` (et le `Requires` du RPM, et le script v2) se **dérivent** de
  `$(REQUIRED_PACKAGES_RUNTIME)` — interdit de les ressaisir à la main. Liste établie en
  auditant les appels du code, pas le script historique : `uml-utilities` conservé mais pour
  `uml_mconsole` (et non `uml_switch`, mort), `xauth` ajouté (cookie X11 lu par `bin/x.ml`),
  `socat` écarté (dépendance invité). Aucun code applicatif touché.
- **2026-08-12 — contrainte entrante : l'installation ne pose aucun client du canal** (§ 2.4 ter,
  neuf). Constat mesuré au sortir de l'épisode 17 de `journalisation-profonde` : aucune cible
  n'installe `useful-scripts/` — ni `marionnet-ctl`/`mrnctl`, ni `mrn-check`/`mrn2sh`, ni le
  `mrn-verify` que cet épisode vient d'ajouter, ni la complétion bash. Or la documentation
  utilisateur les appelle par leur nom nu, et les scripts eux-mêmes se déclarent destinés à
  `$(PREFIX)/bin` — c'est même la justification écrite de leur refus de `bashbricks`. Le § 2.4 ter
  nomme les six fichiers, insiste sur les **deux liens** dont le nom change le comportement
  (`mrn2sh` = `mrn-check --to-bash`, `mrnctl` = `marionnet-ctl`) et corrige le § 2.4 bis sur deux
  dépendances : **`socat`** — écarté le 2026-07-27 comme dépendance *invité*, mais exigé par
  `marionnet-ctl` côté **hôte** — et **`jq`**, requis par les deux vérificateurs. Voie
  d'implémentation à trancher (stanza `install` de dune, ou copie dans `install-final-as-root`).
  Aucun code touché.
- **2026-08-21 — contrainte levée pour `$(PREFIX)/bin/` : les clients du canal et
  `marionnet-cleanup` sont installés** (§ 2.4 ter, encadré « RÉSOLU »). Déclencheur : hors
  chantier, l'avertissement de démarrage sur les répertoires de session laissés en place a reçu
  **deux boutons** (récupérer les projets en `.mar`, puis supprimer les répertoires) qui **lancent**
  `marionnet-cleanup` ; Marionnet ne peut pas nommer et exécuter un outil que l'installation ne
  pose nulle part. Fait : `useful-scripts/dune` (stanza `install`, section `share`, destination
  `scripts/`) pour `marionnet-cleanup`, `marionnet-ctl`, `mrnctl`, `mrn-check`, `mrn2sh`,
  `mrn-verify` ; le mirroir `share/marionnet/scripts/* → $(PREFIX)/bin/` du `Makefile` fait le
  reste, `chmod +x` compris. Restent au chantier : la complétion bash, `socat`/`jq` en dépendances
  **hôte** des paquets, et l'installation de `doc-src/`.
- **2026-08-23 — épisode 1 (hors plan, avant le serveur) : la source de vérité des dépendances
  remise en phase avec le code.** `REQUIRED_PACKAGES_RUNTIME` gagne **`jq`, `socat`,
  `dnsmasq-base`** (§ 2.4 bis, encadré « Ajout du 2026-08-23 »), avec leur justification par site
  d'appel dans le `Makefile` comme pour les neuf autres. Motif : depuis le 2026-07-27, le § 2.4 bis
  fait de cette variable la **seule** source dont dériveront le `Depends` du `.deb`, le `Requires`
  du RPM, la couche runtime Docker et le `apt install` du script v2 — or trois chantiers y avaient
  ajouté des appels hôte sans l'amender, de sorte que `make dependencies` laissait une machine
  fraîche sans DHCP de NAT bridge (`dnsmasq-base`), sans client du canal (`socat`) et sans les deux
  vérificateurs ni les scripts de bridge (`jq`). La NOTE qui écartait `socat` comme dépendance
  *invité* est corrigée sur place plutôt que supprimée : elle disait vrai en 2026-07, elle a cessé
  de l'être quand le canal de contrôle a donné un client à l'hôte. Aucun code applicatif touché ;
  preuve : `make -n -p | grep REQUIRED_PACKAGES_RUNTIME` montre les douze paquets, et
  `make apt-runtime-dependencies` sort en « nothing to do » (les trois sont installés ici).
  **Relevé en chemin, non tranché** : `bridge-utils` n'a plus de site d'appel (`brctl` a disparu du
  code au profit de sysfs) — candidat au retrait, hors périmètre de cet épisode.
- **2026-08-23 — épisode 2 : `bridge-utils` retiré, et les vestiges de `useful-scripts/`
  archivés.** Deux gestes qui n'en font qu'un. Le ménage (fait par l'auteur) sort de l'arbre
  versionné quatre fichiers, dont `prepare_bridge.sh`, le **dernier appelant de `brctl`** ; le
  paquet `bridge-utils`, relevé la veille comme sans site d'appel, perd donc son dernier
  prétexte et quitte `REQUIRED_PACKAGES_RUNTIME` — avec, à sa place dans le `Makefile`, la raison
  du retrait, parce qu'une liste de dépendances ne dit rien sur ce qu'elle ne contient pas.
  Renvois remis d'aplomb dans la foulée : `useful-scripts/dune` ne justifiait plus sa liste
  « deliberately not installed » que par des fichiers absents, et les deux scripts de bridge
  citaient `prepare_bridge.sh` sans dire qu'il n'existe plus. Effet de bord documentaire : ce
  ménage réalise la moitié de l'**étape 5 du plan** (§ 5), et le § 2.5 dit maintenant où chercher
  les satellites encore utiles au chantier (`…_fedora_Sami.sh` pour le RPM, `install_on_site` pour
  l'outillage release) — dans `useful-scripts/BACKUP/`, hors git, sans filet de restitution.
- **2026-08-23 — répercussion (pas un épisode de ce chantier) : les clients ont déménagé dans
  `bin/scripts/`.** Le chantier `move-and-rename-useful-scripts-to-bin-scripts` a appliqué la
  règle fondatrice — `useful-scripts/` = gestion/installation du **projet**, `bin/scripts/` =
  compléments du **binaire** — en ramenant les cinq fichiers concernés, chacun en `.sh` réel
  entouré de **liens symboliques** qui conservent tous les noms d'usage. Conséquences pour ici,
  toutes documentaires : les chemins des § 2.4 bis, 2.4 ter et 2.5 ; `useful-scripts/dune`
  **n'existe plus** (vidé puis supprimé — c'est `bin/dune` qui installe, **vers la même
  destination** `share/marionnet/scripts/`, donc rien à refaire) ; `useful-scripts/` ne suit plus
  que **2** fichiers ; et deux noms neufs (`mrnck`, `mrn-control`) s'ajoutent aux 12 que dessert la
  complétion. **Le reste à faire de ce chantier est inchangé** : la complétion bash n'est
  installée nulle part, `socat`/`jq` ne sont pas déclarés dans les paquets, et `doc-src/` n'est
  pas installé.
- **2026-08-23 — épisode 3 (hors plan) : publier une image invitée devient une commande.**
  `Makefile.d/filesystem.prepare-snapshot-to-publish.sh` (neuf) + cible
  `filesystem.prepare-snapshot-to-publish`. Le geste qu'il remplace était manuel et nulle part
  écrit : prendre le **snapshot** d'un export disque de Marionnet
  (`~/.marionnet/filesystems/<image>_variants/snapshot-*`, un fichier COW), le fusionner avec son
  backing file (`uml_moo`, paquet `uml-utilities` — **déjà** dans `REQUIRED_PACKAGES_RUNTIME`),
  puis reconstituer autour de lui les quatre éléments dont la référence publiée
  `machine-debian-wheezy-08367` donne la forme : l'image nommée par le **premier champ de `sum`**,
  son `.conf` aux empreintes recalculées, son `.relay` s'il y en a un, un `_variants/` vide — plus
  le `.tar.gz` que l'installeur télécharge, aux entrées préfixées `filesystems/` (forme exigée par
  `download_our_large_filesystems`, qui extrait depuis `$PREFIX/share/marionnet/`).
  Trois choix qui ont demandé une mesure, et qu'il faut connaître avant de toucher au script :
  1. **`BINARY_LIST` est recalculée par défaut**, en montant l'image produite en `loop,ro`
     (sudo), sur la définition de `binary_list` de `uml/pupisto.common/toolkit_chroot.sh` élargie
     à `/usr/local/{bin,sbin}` ; `--do-not-update-binary-list` s'en dispense, et le script **dit
     alors explicitement** que la liste héritée peut mentir. Le montage est lecture seule et a
     lieu **avant** le relevé du `MTIME`, que le `.conf` doit porter exactement.
  2. **Le backing file se lit dans l'en-tête du COW, pas dans `file(1)`** : en version 3, le
     chemin est une chaîne NUL-terminée à l'**offset 32** ; `file` tronque le sien vers 96
     caractères, ce qui rend un chemin profond inutilisable (mesuré). `file` ne sert plus que de
     repli, avec le nom du répertoire `<image>_variants` en dernier recours.
  3. **L'idempotence a besoin d'un témoin**, parce que le nom du produit n'est connu qu'**après**
     la fusion (il porte la somme du fichier fusionné) : refaire le `uml_moo` pour découvrir qu'il
     existe déjà coûterait plusieurs gibioctets d'écriture. D'où le fichier caché
     `.<image>.origin`, qui note quel snapshot a produit quelle image ; il n'entre jamais dans le
     tarball. Sans lui, `-f|--force` serait le seul mode utilisable.
  La **série** (`1.0.x`) n'est pas écrite en dur : elle se dérive de `META`, source unique de
  vérité de la version (`X.Y.Z` → `X.Y.x` ; `trunk` → `1.0.x`, la série ouverte par le port dune,
  § 6). La règle a **une seule** implémentation, dans le script (`--print-series`), que le
  `Makefile` interroge pour définir `PUBLICATION_SERIES` — surchargeable
  (`make … PUBLICATION_SERIES=1.1.x`). Le § 3.1 est corrigé en conséquence : les couples vivent
  dans `download/marionnet-install.sh/<série>/`, pas dans un `couples/` séparé.
  Preuve : banc de bout en bout sur une image ext4 synthétique de 16 Mio (`mke2fs -d`, COW par
  `uml_mkcow`) — image nommée par son `sum`, `.conf` dont `SUM`/`MD5SUM`/`MTIME`/`DATE` sont
  **égaux** aux empreintes du fichier produit et dont la structure de clés est identique à celle
  de la source, `.relay` recopié, `_variants/` vide, tarball aux 4 entrées bien préfixées
  `filesystems/` ; deuxième passe → tout sauté, image **inchangée à l'octet et à la date** ;
  `--force` → tout refait. `shellcheck -S warning` : propre.
- **2026-08-23 — épisode 3 (suite) : ce que le run réel a appris, et que le banc ne pouvait pas
  dire.** Le premier passage sur le vrai snapshot trixie (5,4 Gio) s'est **arrêté sur son propre
  garde-fou** (`bash -n` du `.conf` produit) plutôt que de publier un fichier cassé. Deux défauts
  derrière, et un seul était le mien :
  1. **`user_config_set` ne sait pas remplacer une valeur de 30 ko** : il laisse l'ancienne
     affectation en place et en ajoute une seconde, mal formée (anciennes et nouvelles entrées
     entrelacées, quote fermante perdue). Il reste juste pour les scalaires courts — et pupisto ne
     rencontre jamais que son chemin d'**ajout** (il remplit un gabarit où la clé est absente),
     jamais la mise à jour d'une grosse valeur existante. `BINARY_LIST` a donc son propre écrivain
     dans le script.
  2. **Découvert en corrigeant** : la `BINARY_LIST` du `.conf` de `machine-debian-trixie-47362`
     s'étend sur **deux lignes** et s'ouvre sur un `set -hxBE` parasite (un `$-` capturé par erreur
     du côté de pupisto quand l'image a été fabriquée), entrées **dupliquées** de surcroît. Une
     substitution de la seule première ligne laissait donc une queue orpheline et une quote
     déséquilibrée : l'écrivain remplace **toute l'affectation quotée, quel que soit son nombre de
     lignes**. L'image republiée en sort assainie (liste `sort -u`, une ligne, 2 060 binaires),
     mais **le défaut reste dans l'image installée** : à corriger côté `uml/pupisto.debian` à
     l'occasion, sinon chaque nouvelle image le reconduira.
  Résultat du run : `machine-debian-trixie-39212` (5,4 Gio), `.conf` dont `SUM`/`MD5SUM`/`MTIME`
  /`DATE` **égalent** les empreintes du fichier et dont la structure de clés est identique à la
  source, `_variants/` vide, `filesystems_machine-debian-trixie-39212.tar.gz` (1,5 Gio) aux entrées
  préfixées `filesystems/`. Le montage `loop,ro` n'a **pas** bougé le `mtime` de l'image, comme
  voulu. Pas de `.relay` : cette image n'en a pas.
- **2026-08-23 — épisode 3 (fin) : empaqueter une image DÉJÀ publiée, et le `.tar.xz`.** Le script
  ne savait partir que d'un snapshot ; or « donne-moi le tarball de `machine-debian-wheezy-08367` »
  est un besoin distinct et récurrent (image publiée en 2014, image reçue d'ailleurs, `.conf`
  simplement corrigé) pour lequel il n'existait aucun chemin — le détour par un COW vide aurait
  écrit 1,8 Gio pour jeter aussitôt le résultat. L'argument positionnel accepte donc désormais
  **soit** un snapshot **soit** une image publiée ; les deux se distinguent par le **magic COW**,
  pas par un drapeau (rien à retenir), et le mode est **annoncé sur la sortie**. Un nom nu est
  résolu dans le répertoire de sortie, de sorte que `… machine-debian-wheezy-08367` marche depuis
  n'importe où ; en mode image, le répertoire de sortie **suit l'image** sauf `-o` explicite, et
  les membres du tarball sont ceux qui **existent** (une image ancienne peut n'avoir ni `.relay`
  ni `_variants/`). L'option **`--xz`** produit un `.tar.xz` (`xz -T0`, sans quoi la compression
  de plusieurs gibioctets est désespérément monothread) — avec un **avertissement** : l'installeur
  encore en service extrait par `tar xvzf`, donc gzip seulement ; un `.tar.xz` suppose le script
  v2. Preuve : les cinq cas joués au banc (snapshot idempotent, image par chemin complet, `--xz`,
  image par **nom nu** résolu dans `-o`, argument qui n'est ni l'un ni l'autre → refus explicite,
  rc 2), puis la construction réelle des quatre tarballs.
  **Défaut de packaging relevé et corrigé dans la foulée** : le premier tarball wheezy portait
  `jean/jean`, parce que tar recopie l'appartenance des fichiers. Ce qui atterrit dans
  `$PREFIX/share/marionnet/` est de la **donnée système**, extraite par un installeur privilégié
  sur une machine où le compte du empaqueteur ne signifie rien : une archive portant l'uid 1000
  donne ces fichiers soit à un inconnu qui détient cet uid, soit à personne. D'où
  `--owner=root --group=root` à la création. Les **dates**, elles, ne se touchent surtout pas —
  user-mode-linux refuse un backing file dont le `mtime` a bougé, ce qui est toute la raison
  d'être du champ `MTIME` du `.conf` — et le listing le confirme : l'image wheezy garde son
  `2014-06-29 19:02`.
  Mesures des quatre archives (image + `.conf` + `_variants/` + `.relay` s'il existe) :

  | archive | gzip | xz (`-T0`) | gain |
  |---|---|---|---|
  | `filesystems_machine-debian-wheezy-08367` (1,8 Gio) | 560 Mio — 50 s | 404 Mio — 2 min 23 | −28 % |
  | `filesystems_machine-debian-trixie-39212` (5,4 Gio) | 1,5 Gio — 2 min 35 | 1,1 Gio — 7 min 53 | −31 % |

  Le `.tar.xz` **ne remplace pas** le `.tar.gz` tant que l'installeur en service extrait par
  `tar xvzf` : les deux formes cohabitent, et c'est au script v2 de savoir choisir.
- **2026-08-23 — épisode 3 (post-scriptum) : xz devient le DÉFAUT, sur mesure.** L'option a été
  retournée (`--gz` pour du gzip, `--xz` gardé pour l'explicite) après avoir mesuré ce qui
  comptait vraiment : non pas la compression, faite une fois chez nous, mais la **dé**compression,
  faite par chaque étudiant dans le pipeline `wget -O - | tar`. Sur l'image wheezy (1,9 Gio en
  sortie, hôte à 8 cœurs) :

  | décompresseur | temps | CPU |
  |---|---|---|
  | `gzip -dc` | 8,3 s | 99 % (monothread par construction) |
  | `xz -dc -T1` — *ce que fait `tar xJf`* | 21,6 s | 99 % |
  | `xz -dc -T0` | **5,1 s** | 656 % |

  La clé est que **`xz -T0` ne fait pas que comprimer en parallèle : il découpe le flux en
  BLOCS** (76 pour wheezy, `xz --list` le montre), ce qui rend la **décompression** parallèle
  possible — et xz devient alors *plus rapide que gzip*, monothread par nature. En pipeline, la
  seule question est de savoir si le décompresseur suit le réseau : débit d'entrée compressée
  soutenu de 19 Mio/s (`xz -T1`), 68 Mio/s (`gzip`), 80 Mio/s (`xz -T0`). Même au pire cas
  monothread, xz n'est le goulot qu'au-delà de ~150 Mb/s, tout en faisant télécharger 28-31 % de
  moins. **Conséquence pour le script v2** : extraire par `xz -dc -T0 | tar xf -`, jamais par
  `tar xJf -`, sous peine de laisser un facteur 4 sur la table. Le script imprime désormais la
  commande d'extraction qui correspond au format qu'il vient de produire.
- **2026-08-23 — épisode 3 (post-scriptum 2) : les images ROUTER, qui sont des liens.** Appelé
  avec `router-guignol-18474`, le script produisait `filesystems_machine-guignol-18474.tar.xz` —
  il republiait la machine sous le nom de la machine, et le router n'était jamais empaqueté. Deux
  défauts, tous deux dus au fait qu'une image *router* **est un lien symbolique** vers l'image
  *machine* dont elle partage les octets, avec son **propre** `.conf` et son **propre**
  `_variants/` :
  1. `readlink -f` **résolvait le dernier composant** du chemin donné, donc l'identité demandée
     était perdue avant même de commencer. L'argument est désormais rendu absolu **sans**
     déréférencer sa dernière composante.
  2. Une fois le lien archivé, `tar --transform` réécrivait **aussi la cible du lien** (c'est son
     comportement par défaut) : l'archive portait
     `router-guignol-18474 -> filesystems/machine-guignol-18474`, lien **cassé** dès l'extraction.
     Le drapeau **`S`** (`--transform 's,^,filesystems/,S'`) restreint la substitution aux noms
     des membres.
  Le script annonce désormais qu'il empaquette un lien et que l'image pointée doit être installée
  à côté. Preuve : les deux archives guignol extraites côte à côte reconstituent exactement la
  disposition publiée, `.conf` du router **différent** de celui de la machine, et le lien
  **résout**. Les archives wheezy et trixie ne contiennent aucun lien : rien à reconstruire.
- **2026-08-23 — épisode 4 : le `set -hxBE` de la `BINARY_LIST`, une régression de 2014.** Le défaut
  laissé ouvert par l'épisode 3 (« corriger côté `uml/pupisto.debian`, sinon chaque nouvelle image le
  reconduira ») n'était pas dans pupisto.debian : il est dans `uml/pupisto.common/toolkit_chroot.sh`,
  et il a **douze ans**. `git log -L` le date exactement — la ligne s'écrivait
  `echo "set -$-" >> $COOL_SUDO` (`8b814aa`), et le commit `77fb25a` (2014, minimisation de
  debootstrap) a perdu le `>> $COOL_SUDO` en emballant le bloc `export -p` qui la précède dans un
  `{ … } >> $COOL_SUDO`. Depuis, la ligne part sur la **sortie standard** de `sudo_fcall` — ce que
  `BINARY_LIST=$(sudo_chroot_binary_list …)` capture, d'où le `set -hxBE` en tête de liste. Deux
  conséquences que personne n'avait reliées :
  1. **plus aucune option de shell n'était propagée** au script root, ce qui a **silencieusement
     désactivé `BASH_XTRACING`** : le mécanisme pose bien un `PS4` dans le script, mais un `PS4`
     sans `set -x` ne trace rien ;
  2. le `set -` capturé porte `e` ou non **selon le site d'appel** : `$-` perd `errexit` à
     l'intérieur d'une substitution de commande (mesuré), ce qui explique le `set -hxBE` sans `e`
     de l'image `machine-debian-trixie-47362` alors que `pupisto.debian.sh` tourne sous `set -e`.
  **Arbitrage** : la redirection est rétablie, mais les options sont **filtrées** — `e` et `u` sont
  retirés, ainsi que les lettres que `set` refuse (`c`, `i`, `s`, `r`). Restaurer à l'identique
  aurait donné `errexit` aux **autres** sites d'appel, non capturés eux (`sudo_careful_chroot` et
  ses `apt-get` en chroot, `sudo_fcall tabular_file_update`…) : douze ans de fonctions écrites et
  validées sans errexit, dont `careful_chroot` qui **démonte dans son épilogue** — un abandon
  prématuré y laisserait des montages sur l'hôte. Le tracing, lui, revient (`x` est propagé).
  **Second défaut, indépendant** : `binary_list` faisait `sort | tr '\n' ' '` **sans `-u`**, d'où
  les doublons relevés à l'épisode 3 ; une `BINARY_LIST` est un *ensemble* de commandes disponibles,
  pas un recensement d'inodes (sur un système à `/usr` fusionné, `$PATH` nomme deux fois le même
  répertoire). Même correctif dans `pupisto.buildroot.sh`, où un rootfs busybox multiplie les
  basenames.
  Preuve : banc `sudo_fcall` avec un `sudo` mimé (pas de root) et un appelant sous `set -exBE` —
  sur `HEAD`, la sortie capturée est `set -ehxBE\nPAYLOAD` et le script root ne contient **aucune**
  ligne `set -` ; après correctif, la sortie est `PAYLOAD` seule et le script root porte
  `set -hxBE` (`e` filtré, `x` conservé). Dédoublonnage mesuré sur le `$PATH` de l'hôte :
  4 697 → 4 620 entrées, 75 noms dupliqués. `bash -n` propre sur les deux scripts, `shellcheck -S
  warning` sans diagnostic neuf dans le bloc modifié. Les images **déjà publiées** ne sont pas
  touchées : `make filesystem.prepare-snapshot-to-publish` assainit déjà la liste à la
  republication (épisode 3) — ce correctif garantit que les images **à venir** naissent propres.

- **2026-08-23 — épisode 5 : publier un noyau devient une commande.** Le versant *filesystem*
  d'une release était outillé depuis l'épisode 3 ; le versant *noyau* se faisait encore à la
  main. Les quatre fichiers présents dans `download/marionnet-install.sh/1.0.x/`
  (`linux-6.12.95`, `linux-6.12.95-i386` et leurs `.config`) y avaient été déposés un à un, et
  **aucun `kernels_*.tar.*` n'existait** — alors que `download_our_kernels()` de
  `useful-scripts/marionnet_from_scratch` (l. 812-829) cherche exactement
  `href="kernels_*.tar.gz"` et l'extrait depuis `$PREFIX/share/marionnet/`. Autrement dit, le
  répertoire de publication était *incomplet pour l'installeur en place*, sans que rien ne le
  signale.
  `Makefile.d/kernel.prepare-to-publish.sh` (cible `make kernel.prepare-to-publish
  KERNEL=<nom>`) est le pendant de son frère filesystem, et en partage délibérément la forme :
  même bandeau d'usage auto-extrait, mêmes options (`-o -i -s -f -y --no-tarball --xz/--gz`),
  mêmes conventions de tarball — membres préfixés `kernels/` via `--transform 's,^,kernels/,S'`,
  propriété **forcée à root:root** (c'est de la donnée système extraite par un installeur
  privilégié, l'uid de l'empaqueteur n'y veut rien dire), `xz -T0` par défaut, `--gz` pour
  l'installeur du terrain.
  **Ce dont un noyau n'a PAS besoin est ce qui rend le script court** : rien à fusionner, pas de
  `.conf` à écrire, pas de somme dans le nom, et surtout **aucune contrainte de mtime** —
  user-mode-linux ne vérifie la mtime que d'un *backing file*, jamais celle du noyau. Tout le
  travail se réduit à : localiser la paire, la poser où vit la release, l'archiver.
  Trois décisions consignées :
  1. **l'argument est OBLIGATOIRE.** Contrairement à un snapshot de filesystem, dont « le plus
     récent » est un défaut raisonnable, « le » noyau à publier n'existe pas ;
  2. **un noyau, un tarball.** `linux-6.12.95-i386` est un nom à part entière, publié par un
     second appel — pas glissé dans l'archive de `linux-6.12.95`. Deux architectures dans une
     seule archive obligeraient l'installeur à en poser une dont l'utilisateur ne veut pas ;
  3. **la règle de série n'est pas dupliquée** : le script appelle le `--print-series` de son
     frère, lequel déclare explicitement en être la seule implémentation. Deux copies
     divergeraient en silence le jour où `META` bouge.
  Le noyau est **refusé si son `.config` n'est pas à côté** : l'installeur pose toujours la
  paire, et Marionnet lit la configuration pour dire ce que le noyau supporte ; publier un noyau
  seul produirait une installation muette sur ses capacités. Une sonde `file` avertit (sans
  bloquer) quand l'argument n'est pas un ELF exécutable — elle attrape l'erreur classique de
  passer le `.config` à la place du noyau.
  Preuve (run réel) : `kernels_linux-6.12.95.tar.xz` (2,7 Mio) porte exactement
  `kernels/linux-6.12.95` (0755 root/root) et `kernels/linux-6.12.95.config` (0644 root/root),
  identiques octet pour octet aux originaux après extraction ; un second run ne refabrique rien
  (« already there, skipped ») ; `--gz` sur la variante i386 produit
  `kernels_linux-6.12.95-i386.tar.gz` (2,6 Mio), le seul motif que l'installeur en place sait
  voir ; `.config` manquant, noyau inconnu et `KERNEL=` absent sortent tous en **2** avec un
  message explicite ; `shellcheck` propre. Commit `603d2cc`.
  **Reste ouvert** (étape 1 du § 5) : ces tarballs sont fabriqués *localement*. Rien ne les
  dépose encore sur le serveur, et rien ne vérifie que ce qui y est servi correspond à ce que le
  dépôt sait produire — c'est le vrai contenu de la remise à niveau du serveur.

- **2026-08-23 — épisode 6 : consommer une release, et le miroir local.** Les deux commandes de
  publication existaient (ép. 3 et 5) ; **personne ne savait consommer** ce qu'elles produisent.
  Le seul consommateur du dépôt, `useful-scripts/marionnet_from_scratch` (l. 812-899), ne connaît
  que `.tar.gz`, extrait par `tar xvzf` — le facteur 4 mesuré à l'ép. 3 — et ne sait lire qu'un
  listing HTML d'Apache. L'étape 1 du § 5 (« remise à niveau du serveur ») étant **bloquée par
  l'extérieur** (`www.marionnet.org` en panne), cet épisode construit la moitié qui ne l'est pas :
  la couche d'approvisionnement du script v2, avec une source **interchangeable**.
  Livrable : `bin/scripts/marionnet-install.sh`, germe du script v2, n'implémentant que son
  mode `--fetch-only` (toute autre invocation sort en **2** en renvoyant au chantier enfant
  `…-par-script`, qui n'est pas ouvert). Options : `-F|--from URL|DIR`, `-s|--series`,
  `-p|--prefix`, `-l|--list`, `-n|--dry-run`, `-o|--only` / `-x|--exclude` (répétables,
  sous-chaîne), `--no-kernels` / `--no-filesystems`, `--gz`, `-f|--force`, `-y|--yes`.
  Six décisions, chacune payée par un fait :
  1. **La source est un mot, pas un mode** (cf. la note du § 3.1) : `://` ⇒ réseau, sinon
     répertoire, qui doit exister. Deux fonctions seulement en dépendent.
  2. **`.tar.xz` par défaut, extrait par `xz -dc -T0 | tar xf -`, jamais `tar xJf`** — la mesure
     de l'ép. 3 (5,1 s contre 21,6 s) est ici **reproduite** sur l'image wheezy : 5,2 s de temps
     réel pour 32 s de CPU, soit un parallélisme de 6,1. `--gz` existe pour une machine sans `xz`.
     Les deux formes d'un même artefact sont dédupliquées par leur **nom logique** ; le catalogue
     réel en contient trois qui ont les deux.
  3. **`tar xf` sans `-m`/`--touch`, jamais** : le `mtime` est ce que user-mode-linux vérifie sur
     un backing file — raison d'être du champ `MTIME` du `.conf`, et pendant exact du
     `--owner=root --group=root` posé à la **création** (ép. 3).
  4. **Idempotence par le nom, pas par une somme.** `filesystems_<X>.tar.*` pose
     `share/marionnet/filesystems/<X>` et `kernels_<X>.tar.*` pose `share/marionnet/kernels/<X>` :
     la régularité du nommage suffit, aucune lecture du tarball n'est nécessaire pour savoir si
     l'artefact est déjà là. Rien n'est refait sans `--force`.
  5. **Le lien du router est nommé, pas résolu.** `filesystems_router-guignol-18474.tar.xz` ne
     contient qu'un **lien symbolique** vers `machine-guignol-18474`, fourni par un **autre**
     tarball (ép. 3, post-scriptum 2). Deux conséquences dans le script : les images *machine*
     sont extraites **avant** les *router* (le lien résout dès sa création), et une sélection qui
     retient un router sans son image — ni installée, ni sélectionnée — reçoit un **avertissement**
     nommant le lien qui serait posé cassé.
  6. **Le privilège est demandé là où il sert** : `sudo` seulement si la destination n'est pas
     inscriptible. Un `--prefix` sous `/tmp` rend le script entièrement testable **sans aucun
     privilège** — c'est ainsi qu'il a été prouvé.
  **`bashbricks` délibérément écarté**, contre la consigne par défaut du `CLAUDE.md` : ce fichier
  est destiné à être **téléchargé seul** et exécuté sur une machine où le dépôt n'existe pas. Il
  ne peut sourcer aucune bibliothèque de l'arbre. C'est le précédent des clients du canal, en plus
  fort — et c'est écrit en tête du script pour que la question ne se repose pas.
  Preuve : banc jouet (miroir de 4 tarballs fabriqués sur mesure, dont un `.gz` concurrent d'un
  `.xz` et un fichier parasite `README.txt`) — `--list`, `--list --gz`, `--dry-run`, extraction,
  **idempotence** (2ᵉ run : « nothing to do »), `--force`, `--only`/`--exclude`/`--no-kernels`,
  l'avertissement du router orphelin, l'absence de mode (rc 2) et le `--from` inexistant (rc 2).
  Puis **run réel sur le miroir** : guignol + les deux noyaux (4 artefacts, 16 Mio, 0,7 s) →
  image et noyau **identiques octet pour octet** aux originaux (`cmp`), lien `router-guignol-18474`
  qui **résout**, les deux `.conf` bien **différents**, `mtime` de l'image à `2017-06-09` ; puis
  wheezy en `.tar.xz` (403 Mio → 1,9 Gio) → image identique, `mtime` à `2014-06-29`.
  `bash -n` et `shellcheck -S warning` propres.
  **Ce qui n'est PAS prouvé, et ne peut pas l'être aujourd'hui** : le chemin **réseau**
  (`catalog_list` par listing HTML, `artifact_stream` par `wget -O -`) — le serveur est en panne.
  Il est écrit, il n'est pas mesuré ; à jouer dès le retour du serveur, en même temps que
  l'étape 1. Ce que la panne a tout de même appris : **« source injoignable » et « source qui
  répond mais ne contient rien » sont deux échecs différents**, et les confondre envoie chercher
  un défaut de publication là où il n'y a qu'un serveur éteint. `catalog_list` échoue donc
  franchement quand la source ne se lit pas (le listing est récupéré **avant** d'être filtré,
  sans quoi `pipefail` fait passer un `grep` sans occurrence pour une panne de réseau), et le
  catalogue vide a son propre message.
  **Restes ouverts** relevés en chemin : (a) aucun `SHA256SUMS` n'est publié, donc rien ne
  vérifie l'intégrité d'un artefact téléchargé — à faire produire par les deux scripts
  `*.prepare-to-publish.sh`, puis à consommer ici ; (b) la découverte du catalogue par **parsing
  du listing HTML d'Apache** est ce qu'on hérite de 2005 : un fichier d'index publié à côté des
  artefacts serait plus sûr, et se déciderait à l'étape 1 ; (c) `wget` est présumé présent (pas de
  repli `curl`). — *(a) et (b) sont **soldés par l'épisode 8**, et par le même fichier ; (c) reste
  ouvert.*

- **2026-08-30 — épisode 7 : le chemin réseau, mesuré sans le serveur.** L'épisode 6 laissait
  un trou nommé : « le chemin **réseau** est écrit, il n'est pas mesuré ». Il ne concerne que
  **deux lignes** — la branche `url` de `catalog_list` (listing Apache, noms lus dans les
  `href="…"`) et celle d'`artifact_stream` (`wget -q -O -`) — mais ces deux lignes *sont* ce
  qu'est un serveur de release. Plutôt que d'attendre le retour de `www.marionnet.org`, cet
  épisode **dresse le serveur** : un Apache en conteneur, un répertoire de release synthétique,
  et le script lancé depuis un **second** conteneur qui ne contient que Debian et le script.
  Livrable : `bin/scripts/marionnet-install.sh.bench/` (`run.sh`, `Dockerfile.server`,
  `Dockerfile.client`, `README.md`), **16 cas, PASS 16 / FAIL 0**, conventions de
  `driven-sessions/` (0 PASS / 77 SKIP / autre FAIL) — mais **pas** dans `driven-sessions/`,
  qui est scopé aux sessions Marionnet pilotées : le banc vit à côté de ce qu'il prouve, d'où
  les trois entrées de liste blanche dans `.gitignore`.
  Trois décisions, chacune payée par un fait :
  1. **Apache, et jamais `python3 -m http.server`.** Le parsing vise un listing d'Apache, le
     script le dit lui-même. `FancyIndexing` est activé **exprès** parce que c'est le listing
     difficile — et la mesure l'a confirmé : ses liens de tri `href="?C=D;O=A"` sont bel et bien
     dans la page (vus en clair quand le mutant « filtre neutralisé » les a laissés passer). Un
     banc servi par un autre listing aurait mesuré un analyseur contre une page que personne ne
     publiera.
  2. **HTTP, pas HTTPS.** Un certificat auto-signé forcerait `wget --no-check-certificate`,
     c'est-à-dire mesurerait une commande **différente** de celle qui tournera en production. La
     jambe https est une vérification d'une ligne contre le vrai site, à son retour.
  3. **Rien n'est monté dans le client** hormis le script : ni miroir, ni dépôt. Ce qui arrive
     dans son préfixe est passé par HTTP, ou n'est pas arrivé. Corollaire utile au chantier : le
     client ne porte que `wget`, `tar`, `xz-utils`, donc les dépendances hôte du chemin
     d'approvisionnement sont **mesurées** au lieu d'être supposées.
  **Discriminance mesurée (rouge/vert), parce qu'un banc vert des deux côtés ne prouve rien** :
  `tar xmf` (`-m`) → le cas `mtime` tombe ; filtre `case` neutralisé → les deux cas du catalogue
  tombent, parasites *et* `?C=…` ; échec `wget` avalé (`|| html=""`) → les cas 4a et 5a tombent
  ensemble, ce qui est exactement la leçon de l'ép. 6 ; avertissement du router supprimé → le cas
  du router seul tombe.
  **Fait mesuré et assumé, contre l'intuition** : l'ordre d'extraction (machines avant routers)
  est **inobservable** quand les deux tarballs sont pris — le banc reste vert avec les deux
  passes inversées, le lien transitoirement cassé étant résolu par l'extraction suivante. Ce qui
  est observable, c'est le router pris **seul**, d'où le cas qui vérifie l'**avertissement** et
  non l'ordre. Le libellé du cas voisin a été corrigé en conséquence : il prouve que le router
  arrive *en tant que lien* et que sa cible est là, pas un ordre.
  **Découverte de l'épisode — un piège de production qu'aucun miroir ne pouvait montrer** : un
  `index.html` déposé dans le répertoire de release fait servir **la page au lieu du listing**,
  avec un `200`. Les artefacts sont là, le catalogue revient **vide**, et rien n'est cassé côté
  publication. Le script s'en sort correctement (message « answered, but holds no… », rc 2), mais
  c'est l'argument le plus concret en faveur du **reste ouvert (b) de l'ép. 6** : publier un
  **fichier d'index** à côté des artefacts plutôt que dépendre de `mod_autoindex`. Le cas est
  versionné comme piège vivant. Symétriquement, `Options -Indexes` (403) sort bien par
  « cannot read the catalogue » — et sert de **témoin de discriminance** : s'il passait comme
  le cas nominal, c'est que le cas nominal n'aurait jamais lu de listing.
  **Reste ouvert relevé en chemin** : `artifact_size` ne sait rien sur HTTP (`url) : ;;`), donc
  `--list` affiche une taille vide et le plan annonce « 0 B to transfer » — or c'est le chiffre
  que l'utilisateur lit avant d'accepter. Un `wget --spider -S` donnerait le `Content-Length`.
  **Non prouvé, et ne le sera qu'avec le vrai serveur** : la configuration réelle de
  `www.marionnet.org` (son autoindex peut être désactivé ou habillé) et la jambe **https**.
  Ce banc mesure le **mécanisme**, pas la cible.
  **Point de méthode noté au passage** : l'option demandée (« passer l'adresse d'un serveur
  local ») **existait déjà** — `--from` n'est pas un mode mais un mot, `://` suffit à basculer.
  L'ajouter aurait dupliqué l'option et créé deux façons de dire la même chose.

- **2026-08-30 — épisode 7 bis : la taille d'un artefact sur HTTP.** Le reste ouvert relevé une
  heure plus tôt : `artifact_size` ne savait rien sur HTTP (`url) : ;;`), donc `--list` affichait
  `?` et le plan annonçait « **0 B to transfer** » — or c'est le seul chiffre que l'utilisateur
  lit avant d'accepter le transfert, et « 0 » est un mensonge là où « inconnu » était la vérité.
  Corrigé par un **HEAD** : `wget --spider -S`, dont on lit le `Content-Length`.
  Trois choses que la mesure a imposées :
  1. **Le dernier `Content-Length`, pas le premier** : `-S` écrit les en-têtes sur **stderr**, et
     une redirection en imprime un jeu **par saut** ; seul le dernier décrit le corps. D'où le
     `tail -n 1`, et un `-T 10 -t 2` parce que la sonde tourne une fois par artefact **avant**
     tout transfert : un serveur lent doit coûter un instant, pas un blocage.
  2. **Une taille inconnue reste montrée comme inconnue.** Un serveur qui refuse le HEAD, ou qui
     annonce un corps *chunked*, ne répond rien : `human` imprime `?` comme avant. Ce qui change,
     c'est le **total** : il ne sous-compte plus en silence. Zéro taille manquante → le total ;
     quelques-unes → « **at least X to transfer (N of unknown size)** » ; toutes → « **size
     unknown** ». Vérifié à l'écran dans les trois cas.
  3. **Le banc ne réimplémente pas l'arithmétique** : il fait décrire **le même répertoire** par
     les **deux** branches d'`artifact_size` (HTTP et miroir) et exige qu'elles s'accordent
     colonne par colonne. Une comparaison de deux implémentations vaut mieux qu'une constante
     recopiée dans le banc.
  Le banc passe de 16 à **20 cas** (PASS 20 / FAIL 0). Discriminance mesurée : la branche `url`
  remise muette fait tomber **exactement** les 3 cas neufs de taille (1c-1e), les 16 autres
  restant verts ; l'ancien message restauré fait tomber le 4ᵉ (1f).
  **Piège d'implémentation du banc, payé par un échec** : `mod_autoindex` **retire du listing ce
  qu'il ne peut pas `stat`**. Un lien symbolique cassé — première idée pour fabriquer un artefact
  de taille inconnue — n'atteint donc **jamais** le catalogue, et le cas passait à côté de son
  sujet (mesuré : 4 artefacts listés au lieu de 5). L'artefact de taille inconnue est donc un
  fichier bien réel mais **illisible** (mode 000 ⇒ 403), ce qui est aussi le cas de terrain :
  un artefact déposé avec de mauvaises permissions.

- **2026-08-30 — épisode 8 : le catalogue devient un fichier publié, et il porte l'intégrité.**
  L'épisode 6 laissait deux restes ouverts, (a) « aucun `SHA256SUMS` n'est publié » et (b) « la
  découverte du catalogue par parsing du listing d'Apache est ce qu'on hérite de 2005 ».
  L'épisode 7 avait transformé (b) en défaut **mesuré** : un `index.html` dans le répertoire de
  release fait servir la page au lieu du listing, avec un `200`, donc un catalogue **vide** sans
  rien de cassé côté publication ; `Options -Indexes` casse par l'autre bout. Les deux se
  soldent par le **même fichier**, et c'est la décision de l'épisode : une ligne `sha256sum`
  porte un **nom** *et* une **empreinte**, donc `SHA256SUMS` répond aux deux questions que pose
  l'installeur. Publier un index **et** un fichier de sommes aurait créé deux vérités capables
  de diverger.
  Livrables : `Makefile.d/release.sha256sums.sh` (neuf, le seul écrivain) + cible
  `make release.sha256sums` ; les deux `*.prepare-to-publish.sh` l'appellent après avoir déplacé
  leur tarball ; `bin/scripts/marionnet-install.sh` le lit comme **catalogue** et vérifie
  chaque artefact **en flux** ; le banc passe de **20 à 31 cas** (PASS 31 / FAIL 0).
  Cinq décisions, chacune payée par un fait :
  1. **Un troisième script, pas une fonction dupliquée.** Les deux publieurs dupliquent déjà
     `publication_series` ; ce qui a tranché n'est pas le style mais un besoin : les artefacts
     **déjà publiés** (wheezy, guignol, les noyaux) n'ont aucune somme, et il faut pouvoir
     **amorcer** le fichier d'un répertoire existant. Un écrivain appelable seul était donc
     nécessaire de toute façon.
  2. **Rien n'est recalculé sans `--force`** : un digest, c'est relire le fichier entier, et un
     tarball d'image pèse des gibioctets. Même raisonnement que le témoin `.<image>.origin` de
     l'ép. 3. Mesuré sur le miroir réel : les 10 artefacts (3,7 Gio) amorcés en 3,3 s, puis
     « nothing to do » ; l'ajout d'un onzième ne touche pas aux dix autres.
  3. **Une ligne orpheline est retirée, pas gardée.** Puisque le fichier **est** le catalogue,
     une ligne survivant à un artefact supprimé annonce un fantôme. Le retrait n'a lieu que
     lorsque le script a regardé **tout** le répertoire : un appel qui nomme un tarball frais ne
     sait rien des autres.
  4. **La vérification se fait EN FLUX, et `tee >(sha256sum)` ne convient pas.** Le tarball
     n'est jamais posé sur disque (choix de l'ép. 6, que 1,5 Gio de fichier temporaire pour
     vérifier avant d'extraire défairait) ; l'empreinte se calcule donc **pendant** l'extraction. Mais
     bash **n'attend pas** une substitution de processus : la comparaison pourrait lire un digest
     inachevé. D'où un **fifo explicite**, un pid, un `wait`. Trois issues distinctes sont
     rendues au lecteur — digest conforme, digest en écart, transfert/extraction en échec —
     parce que les confondre enverrait chercher une panne réseau là où il y a un tarball corrompu.
  5. **Un artefact qui rate son digest est RETIRÉ.** Le run est idempotent **par le nom** de la
     cible (ép. 6, décision 4) : le laisser en place le ferait passer pour installé à tout jamais.
     Retirer la seule cible suffit — un run suivant réécrit `.conf` et `_variants/`. `--no-verify`
     existe pour l'utilisateur qui sait mieux, et l'absence de `sha256sum` **dégrade** (message)
     au lieu d'échouer.
  **Ce que le digest ne prouve pas, et il faut le dire** : la **provenance**. `SHA256SUMS`
  emprunte la même route que les tarballs, donc un serveur compromis réécrit les deux. Il prouve
  que l'artefact est **arrivé entier**. La signature est une question pour l'étape 1, avec la
  clef du dépôt apt.
  **Discriminance mesurée**, comme à l'ép. 7 : lecture de `SHA256SUMS` rendue muette → **7 cas**
  tombent (les trois du catalogue publié, celui du digest annoncé, la vérification, l'écart et
  le retrait), les 24 autres restent verts — c'est exactement l'état d'avant l'épisode ;
  comparaison neutralisée → 2 cas ; retrait de la cible supprimé → 1 cas.
  **Mesuré et assumé, deuxième de la famille ouverte à l'ép. 7** : retirer le `wait` du hacheur
  laisse le banc **vert**. Le `sha256sum` voit l'EOF dès que `tee` ferme le fifo et a fini
  d'écrire avant qu'on le lise : sur 294 kio la course ne s'ouvre pas. Le `wait` reste, parce
  que cette course se paierait sur 1,5 Gio par un digest **vide**, donc un **faux** écart, donc
  la destruction d'un artefact sain. Un invariant peut être une course : le banc dit qu'il ne
  sait pas la voir, pas qu'elle n'existe pas.
  **Deux pièges payés par un échec pendant l'épisode** : (1) `awk '{print $1}' -- fichier` —
  `awk` ne connaît pas `--` et cherche un fichier nommé `--`, ce qui faisait échouer **toute**
  vérification en la présentant comme un écart de somme (donc en supprimant un artefact sain) ;
  (2) dans le banc, corrompre un digest par `sed 's/^0/1/; s/^[1-9a-f]/0/'` rend l'**original**
  — la seconde substitution s'applique au résultat de la première — et le cas passait pour la
  mauvaise raison. Corrigé par `awk`, avec deux gardes : la ligne reste à 64 chiffres
  hexadécimaux, et le fichier corrompu doit **différer** de l'original sous peine de `SKIP`.
  Preuves : les 4 scripts propres à `bash -n` et `shellcheck -S warning` ; banc jouet du script
  de sommes (amorçage, incrément sans recalcul, `--force`, `--dry-run`, `--check`, format accepté
  par le `sha256sum -c` du système, artefact hors répertoire refusé rc 2) ; run réel sur le
  miroir `website-repo/…/1.0.x/` (10 artefacts, colonne `SUM` à `yes`, installation vérifiée de
  guignol + noyau i386 dans un préfixe `/tmp`, donc **sans privilège**, puis « nothing to do ») ;
  chemins d'échec joués sur miroir (somme fausse → rc 2 + cible retirée, `--no-verify` → installe,
  pas de `SHA256SUMS` → repli annoncé) ; **banc HTTP complet PASS 31 / FAIL 0** et les trois
  mutants ci-dessus.
  **Reste ouvert de l'ép. 6 encore ouvert** : (c) `wget` présumé présent, pas de repli `curl`.

## Épisode 9a (2026-08-30) — l'application devient un artefact publiable

Étape 2 du § 5. Une release savait poser des **ressources** (images, noyaux) pour un programme
qu'il fallait encore compiler ; elle contient désormais le programme. Livrables :
`Makefile.d/release.binary.sh` (neuf), cibles `make release-binary` et
`make print-required-packages-runtime`, plus le **troisième préfixe** reconnu par
`Makefile.d/release.sha256sums.sh`.

### Ce que le script fait, et pourquoi ce n'est pas seulement `dune install`

`dune install --prefix` **n'est pas** une installation de Marionnet : `install-final-as-root`
du `Makefile` fait deux gestes de plus, et le tarball doit faire les mêmes.

1. **Les scripts de `bin/scripts/` vont dans `bin/`.** dune les installe sous
   `share/marionnet/scripts/` (ce sont des fichiers de données de la section `share`), qui
   n'est sur le `PATH` de personne — alors que Marionnet, la règle sudoers et la documentation
   livrée les nomment **nus**. La copie est un `cp -a`, non le `cp -lf` du `Makefile` : un lien
   dur a un sens sur un système installé (un inode, deux noms), aucun dans un staging qu'on va
   archiver. Ce que `-a` préserve et qui compte, ce sont les **liens symboliques** — et pour
   `mrn2sh` et `mrnck`, **le nom est le comportement** (`${0##*/}`).
   *Mesuré au passage* : `dune install` **déréférence** ces liens (chaque nom arrive en fichier
   régulier complet). Le comportement reste juste — chaque nom est exécutable et se lit
   lui-même — mais l'installation pèse quelques dizaines de kio de plus. C'est le comportement
   de l'installation réelle, pas une divergence introduite ici.
2. **La règle sudoers appartient à la machine cible**, pas à celle qui empaquette : elle
   déménage dans l'`install.sh` embarqué, toujours **sans** `--enable-bridges` (bloc (a) seul).

### Les décisions, et ce qui les a payées

- **Une racine nommée dans le tarball**, là où les deux frères se déplient droit à
  destination : ceux-là portent des données à place fixe, celui-ci porte une **installation
  entière**. Un tarball qui verse `bin/` et `share/` dans `/usr/local` ne se regarde pas avant
  d'être cru et ne laisse rien à désinstaller. La racine donne aussi un toit à `install.sh`.
- **La glibc dans le nom, pas la distribution** : ce qu'un binaire dynamiquement lié exige de
  sa machine d'accueil est une glibc au moins aussi récente que celle contre laquelle il a été
  lié. `debian13` nommerait une distribution qui n'est pas la contrainte et ne dirait rien
  d'Ubuntu ou de Mint.
- **La configuration *testing* est refusée par défaut.** `CONFIGME.choice` décide du préfixe
  **compilé** dans `bin/meta.ml` : en *testing* c'est `$OPAM_SWITCH_PREFIX`, un chemin sous le
  home de qui empaquette. Un tel tarball n'est pas faux pour son auteur — et il est même le
  moyen d'éprouver ce script — mais il ne doit **jamais** atteindre un répertoire de release.
  D'où : autorisé par `--allow-testing-configuration`, qui **exige** un `--output-dir` explicite
  et **n'inscrit rien** au catalogue. Le script ne bascule pas la configuration lui-même :
  `make rebuild-for-final` est un rebuild complet, c'est une décision, pas un effet de bord.
- **La liste des paquets d'exécution est lue, pas recopiée** : le README embarqué la reçoit de
  `make print-required-packages-runtime` (cible neuve), parce que la machine qui déplie le
  tarball n'a pas de `Makefile` à lire. La source de vérité (§ 2.4 bis) reste unique.
- **Pas de bashbricks**, comme les trois autres scripts de `Makefile.d/` : aucun d'eux ne source
  quoi que ce soit, et la famille vaut mieux que la consigne par défaut.

### Le défaut que l'épisode a mis au jour : `--paths` ment quand le binaire est relogé

En dépliant le tarball sous un préfixe **autre** que celui de compilation, `marionnet.native
--paths` montre `filesystems`, `kernels`, `gui`, `images` correctement relogés (la cascade de
`bin/configuration.ml` fait son travail) mais laisse **`binaries` au préfixe compilé** —
`bin/initialization.ml:472` le calcule par `Filename.concat Meta.prefix "bin"`.

Vérification faite, ce n'est **pas** un défaut de relocatabilité : cette valeur ne sert qu'à
l'affichage de `--paths`, et les scripts compagnons sont appelés **par leur nom nu**
(`bin/tap_provider.ml:48`, `bin/nat_bridge_host.ml:46`, `bin/lan_bridge_host.ml`), donc trouvés
par le **`PATH`**. Deux conséquences, une pour chacun des deux versants :

- *pour l'utilisateur* : un préfixe hors `PATH` donne un Marionnet qui démarre et qui, ensuite,
  ne trouve plus ses portes privilégiées. L'`install.sh` embarqué **le dit** désormais, en
  nommant les scripts concernés ;
- *pour le code* : la ligne `binaries` de `--paths` annonce un répertoire que rien ne lit.
  Laissée en l'état (la corriger est un choix de sémantique — le répertoire du binaire courant ?
  celui où le `PATH` trouve `marionnet-sudoers.sh` ?), notée ici pour ne pas être redécouverte.

### Prouvé

`shellcheck` rc 0 sur le script **et** sur l'`install.sh` embarqué (extrait de son
here-document et vérifié séparément). Les **3 gardes** en rc 2 : *testing* refusé,
`--allow-testing-configuration` sans `--output-dir`, option inconnue. Un défaut d'écriture
corrigé en chemin : `usage` déroulait aussi l'usage de l'`install.sh` du here-document — la
plage `sed` est ancrée sur `Usage: Makefile.d`.

Run réel (configuration *testing*, hors release, `--output-dir` explicite) : **7,1 Mio en 15 s**,
`marionnet_trunk-r905_amd64_glibc2.39.tar.xz`, **tous les membres root/root**, 23 noms dans
`bin/` (le binaire, les 15 noms de `bin/scripts/`, `bashbricks.sh` et les `.sh` réels),
324 entrées sous `share/marionnet/` dont `share/marionnet.conf`, le glade et les catalogues
`.mo`. Déplié sous un préfixe arbitraire, `install.sh --no-config --no-sudoers` pose l'arbre et
`marionnet.native --help` **répond** (rc 0). Relocation mesurée par `--paths`, avec et sans les
variables (cf. ci-dessus). Idempotence : second run « already there, skipped » ; `--force`
refait. Catalogue : `release.sha256sums.sh` accepte le `marionnet_*` (1 artefact calculé) et
`--check` le valide.

**Non prouvé, faute d'y être** : le chemin **nominal** (configuration *finale*, inscription
automatique au `SHA256SUMS` du vrai répertoire de release) — il demande un `make
rebuild-for-final`, donc un rebuild complet de la copie de travail ; seule la branche
d'inscription diffère, et elle a été jouée à la main.

### Restes

- ~~**Épisode 9b** : le banc conteneur vierge~~ **fait le 2026-08-30** (§ suivant).
- ~~**Épisode 9c** : le troisième préfixe côté consommateur~~ **fait le 2026-08-30**
  (§ « Épisode 9c » ci-dessous).
- Toujours ouverts : le repli `curl` de l'ép. 6, la complétion bash (§ 2.4 ter), et l'étape 1
  (dépôt sur le serveur), bloquée par l'extérieur.

## Épisode 9b (2026-08-30) — la machine cible : `install.sh` joué **en root**

Le banc `Makefile.d/release.binary.sh.bench/` (Dockerfile + `run.sh` + README), frère de
celui de l'épisode 7 : une `debian:trixie-slim` qui ne porte que
`REQUIRED_PACKAGES_RUNTIME`, deux conteneurs `--network none`, rien de monté que le
tarball en lecture seule. **27 cas, tous verts**, `rc 0`.

Le chemin **nominal** de fabrication, laissé non joué par 9a, l'est enfin : `make
rebuild-for-final` puis `make release-binary`, donc préfixe compilé `/usr/local` et
**inscription automatique** au `SHA256SUMS` du vrai répertoire de release (11 artefacts,
1 calculé).

### Ce que le banc a trouvé — et c'est un défaut de fond, pas un détail

La liste de dépendances d'exécution était écrite par des gens qui **compilaient**. Deux
paquets y manquaient, tous deux invisibles tant qu'installer voulait dire compiler :

- **`xz-utils`** : tous les artefacts publiés sont des `.tar.xz` par défaut, et le README
  du tarball prescrit `tar xf` — qui meurt en `xz: Cannot exec` sur une Debian nue. `tar`
  est `Essential: yes`, `xz` ne l'est pas. Mesuré, pas supposé.
- **`libgtksourceview-3.0-1`** : les bibliothèques GTK arrivaient jusqu'ici comme
  dépendances de `REQUIRED_PACKAGES_BUILD` (`liblablgtk3-ocaml-dev`) ; une machine qui ne
  fait qu'**exécuter** n'a pas ce paquet de build, et le binaire mourait sur
  `libgtksourceview-3.0.so.1`. `objdump -p` liste **13** bibliothèques `NEEDED` directes ;
  ce **seul** paquet les apporte toutes, étant le seul qui dépende de gtk3, lequel dépend
  du reste. Nommé plutôt que `libgtk-3-0` : ce dernier a gagné un suffixe `t64` en
  trixie/noble et ne l'avait pas en bookworm, alors que celui-ci est stable sur les trois —
  apt résout alors le gtk3 de la version qu'il a.

Les deux sont dans le `Makefile`, avec leur justification par site d'appel, comme les
douze autres (§ 2.4 bis). Le README du tarball, qui **lit** cette liste, les annonce donc
sans qu'on l'ait touché.

### Le second défaut : republier laissait le catalogue mentir

`release.binary.sh --force` refait le tarball ; `release.sha256sums.sh`, lui, **garde** un
digest déjà enregistré (il ne relit pas des gibioctets sans raison). Conséquence mesurée :
après une republication sous le même nom, `SHA256SUMS` annonçait le digest de l'artefact
**précédent** — `sha256sum -c` en échec, et surtout un installeur qui vérifie l'empreinte
**pendant** l'extraction (ép. 8) et **retire** ce qu'il vient de télécharger. Une release
qui a l'air publiée et qui est inutilisable.

Le correctif est le même dans les **trois** publieurs (`release.binary.sh`,
`filesystem.prepare-snapshot-to-publish.sh`, `kernel.prepare-to-publish.sh`) : l'appel au
catalogueur passe `--force`, **borné à ce seul fichier**. Le raisonnement est celui qui
rend le correctif sûr : à cet endroit, le publieur **vient d'écrire** le fichier, donc un
digest enregistré sous ce nom est *par construction* celui d'avant. Borné, les gibioctets
voisins ne sont pas relus. Le banc en garde un cas, joué **avant** les conteneurs.

### Les 27 cas

Dépli et racine nommée ; `--help` (une seule ligne `Usage:`, la plage `sed` reste ancrée) ;
les **trois refus** (hors tarball, sans root, sans `SUDO_USER` ni `USER`) ; l'installation
nominale (23 noms, tous `root:root`, compagnons sous leur nom nu) ; la configuration
(écrite, nommant le préfixe, **intacte** au second passage, réécrite sous `--force`,
absente sous `--no-config`) ; la **règle sudoers** (fichier propre, `visudo -c` vert,
accordée à l'utilisateur que `sudo` nomme, **bloc (a) seul** — ni natbridge ni lanbridge —,
retirée par `marionnet-sudoers.sh uninstall`, non posée sous `--no-sudoers`) ; le binaire
qui **démarre** avec la seule liste publiée ; le préfixe inhabituel `/opt/marionnet` (la
configuration le suit, l'avertissement PATH est émis, et rien de son `bin/` n'est joignable
par nom nu) ; enfin le **piège durable de 9a inscrit en cas** : `--paths` reloge
`filesystems`/`kernels`/`gui` et continue d'annoncer un `binaries` au préfixe **compilé**.

### Ce que ce banc ne mesure pas

Aucun invité, aucun tap, aucune GUI : le conteneur n'a pas de serveur X. Le banc s'arrête à
ce qu'une machine cible reçoit et à ce que le binaire fait sans afficher.

## Épisode 9c (2026-08-30) — le troisième préfixe, côté consommateur

Depuis l'épisode 9a une release publie **trois** familles dans le même répertoire et le même
`SHA256SUMS`. `bin/scripts/marionnet-install.sh` en connaissait deux et **laissait tomber
la troisième sans rien dire** : l'application était catalogable et non installable par le
script qui la voit. C'est fini — `--binary`.

### Pourquoi une option, et pas un élargissement de `--fetch-only`

Les deux premières familles portent des **données**, dont la place est fixée sous
`<prefix>/share/marionnet/` et que quiconque peut y écrire pose lui-même. La troisième porte
une **installation** : elle écrit `<prefix>/bin/`, `/etc/marionnet/marionnet.conf` et une
règle sudoers, et elle exige root. Replier cela dans une option **déjà publiée** aurait changé
ce que cette option fait sur les machines qui la lancent déjà. Les deux modes se **cumulent**
(`--fetch-only --binary`), ce qu'une machine neuve demande en réalité ; sans mode, le script
dit lequel donner et sort 2 — l'ancien message renvoyant à l'enfant `…-par-script` ne vaut
plus que pour les **dépendances apt** de l'hôte, tout ce qu'il reste à cet enfant de ce côté.

### Le choix, lu dans le nom et nulle part ailleurs

Le nom que `release.binary.sh` a écrit porte tout : `marionnet_<version>-r<rev>_<arch>_glibc<x.y>`.
Un artefact est **candidat** quand son `<arch>` est celle de la machine et que son `<x.y>` n'est
pas plus récent que la glibc de la machine (un binaire lié dynamiquement exige une glibc au
moins aussi récente que celle contre laquelle il a été lié ; l'autre sens est ce que garantit le
versionnement de symboles). Parmi les candidats, **le plus grand `rev`** l'emporte : c'est le
seul champ totalement ordonné du nom. Les deux faits de l'hôte sont lus **comme
`release.binary.sh` les a lus** pour nommer le tarball (`dpkg --print-architecture`,
`ldd --version`) — les lire autrement ici comparerait deux choses différentes. Une glibc hôte
**illisible** ne rejette rien : refuser tout sur cette base serait une devinette.

Ce qui est écarté est **montré** comme écarté par `--list`, avec son critère (`not i386`,
`needs a newer glibc than 2.41`, `superseded`) : une machine i386 et une glibc trop vieille ne
se soignent pas pareil, et un catalogue qui cache ce qu'il refuse ment. Le refus global, lui,
est prononcé **après** `--list` — quand rien de publié ne tourne ici, le listing est exactement
ce que le lecteur veut voir.

### Ce que le script fait, et surtout ce qu'il ne fait pas

Il déplie l'artefact **à côté** (`mktemp -d`), puis lance l'`install.sh` **qui voyage dedans**.
Deux raisons, et la seconde est la plus importante :

1. cet artefact porte une **racine nommée** et une installation entière, pas des fichiers de
   données dont la place est fixe : le déplier là où il va déverserait `bin/` et `share/` sur
   le système avant toute vérification, sans rien laisser à regarder ni à retirer ;
2. **l'installeur reste unique.** Celui qui télécharge le tarball à la main lance ce même
   `install.sh` ; si ce script-ci reposait le préfixe, la configuration et la règle sudoers
   à sa façon, il y aurait **deux** installeurs à maintenir d'accord. Il n'en pilote qu'un,
   et lui relaie `--force`, `--no-sudoers`, `--no-config`.

Le digest est vérifié **en flux** comme pour les deux autres familles (`extract_verified` a
gagné son répertoire de destination et le droit de se passer de `sudo` — le dépli temporaire
n'en demande aucun). Différence utile : en cas d'écart, il n'y a **rien à retirer**, puisque
rien n'a touché le système. L'idempotence reste **par le nom** — ici `<prefix>/bin/marionnet.native` :
on ne compare pas de version, le fichier installé ne disant pas de quel tarball il vient.

Enfin l'application est transférée **en premier** quand les trois familles sont demandées :
c'est l'étape courte et privilégiée, et une machine qui ne peut pas la recevoir doit l'apprendre
**avant** que des gibioctets d'images aient voyagé.

### Prouvé

- Le banc réseau passe de **31 à 50 cas**, tous verts, `rc 0` — section 7 :
  non-régression de `--fetch-only` sur une release à trois familles, le choix et ses quatre
  états, l'installation par HTTP (préfixe transmis, `uid=0`, dépli **hors** du préfixe, rien
  laissé derrière), l'idempotence, les trois passe-plats, le refus motivé, le digest en écart
  qui n'installe rien, et les deux modes en un seul run. **Discriminance : 16 échecs** contre le
  script d'avant.
- **La chaîne réelle, de bout en bout**, hors banc : le **vrai** `marionnet_trunk-r906_amd64_glibc2.39.tar.xz`
  de la release locale, servi en miroir, installé **en root** dans le conteneur cible de
  l'épisode 9b (`debian:trixie-slim` + les seuls `REQUIRED_PACKAGES_RUNTIME`) sous
  `--prefix /opt/marionnet` : `ok, verified`, `install.sh` joué, `/etc/marionnet/marionnet.conf`
  écrit, `/etc/sudoers.d/marionnet` posé pour l'utilisateur que `sudo` nomme, `visudo -c` vert,
  23 noms dans `bin/`, et `marionnet.native --version` qui répond `trunk revno 906`. C'est la
  jonction 9a → 9b → 9c mesurée d'un seul geste.

### Ce que ce banc ne mesure pas

Les tarballs de la famille y portent un `install.sh` **sonde** : ce que la section 7 mesure est
le **contrat** (racine nommée, `install.sh --prefix DIR`, root), pas ce que fait le vrai — celui-là
est mesuré par `Makefile.d/release.binary.sh.bench/`, sur un vrai tarball, et il n'y a pas de
raison de le mesurer deux fois. La jonction des deux, elle, est le geste réel ci-dessus.

### Restes

- Le repli `curl` (ép. 6), la complétion bash (§ 2.4 ter), la **signature** des artefacts.
- **Les dépendances apt de l'hôte** : `--binary` installe l'application, pas ce qu'elle exige.
  C'est ce qu'il reste à l'enfant `…-par-script`, et c'est aussi ce que le `.deb` fera tout seul.
- L'étape 1 (dépôt sur le serveur) et la jambe **https**, bloquées par l'extérieur.

## Épisode 10 (2026-08-31) — les dépendances apt de la machine cible

L'épisode 9c posait l'application sur la machine du consommateur ; il ne posait pas ce
qu'elle **exige**. Le reste était écrit noir sur blanc au § « Restes » de 9c : *« `--binary`
installe l'application, pas ce qu'elle exige »*. C'est ce que cet épisode solde, du côté du
tarball binaire — donc pour **les deux** chemins d'installation, celui de l'humain qui
déplie à la main et celui de `marionnet-install.sh --binary`, puisqu'il n'y a **qu'un**
`install.sh`.

### La liste voyage comme donnée, pas comme prose

Avant cet épisode, `REQUIRED_PACKAGES_RUNTIME` arrivait dans le tarball **en prose**, dans le
`README` (`Makefile.d/release.binary.sh`, l. 292). Un humain la lit ; un programme, non.
L'`install.sh` embarqué ne pouvait pas non plus la porter en dur : son here-document est
**quoté à dessein** (`<<'INSTALL_SH_EOF'` — rien du shell de l'empaqueteur ne fuit dans le
script que l'utilisateur exécute), donc l'y écrire aurait voulu dire **recopier la liste à la
main**, c'est-à-dire refaire le défaut que l'épisode 1 a réparé.

D'où un **fichier de données** dans le tarball, à côté d'`install.sh` :

```
<name>/REQUIRED-PACKAGES-RUNTIME    un paquet par ligne, commentaires permis
```

écrit par le même `make print-required-packages-runtime` qui alimente déjà le `README`. La
source de vérité reste unique : le `Makefile`. Le banc le **vérifie** (cas 28 : la liste du
tarball, triée, est celle du `Makefile`), ce qui rend la dérive impossible en silence.

### Nommer, pas installer — et pourquoi ce n'est pas le défaut inverse

Défaut d'`install.sh` : il **nomme** ce qui manque et donne la commande `apt` toute prête ;
il n'installe rien. `--with-deps` installe ; `--no-deps` ne regarde même pas.

Le motif est le même que celui qui a fait refuser, à l'épisode 9a, que l'`install.sh` du
tarball fasse plus que poser une installation : *poser une application* et *tirer une
douzaine de paquets* sont **deux gestes**, et seul le premier a été demandé. Le canal dont
c'est justement le rôle de faire les deux, c'est le `.deb` (§ 4, enfant `…-par-paquet-deb`),
où `Depends:` le fait sans que personne l'écrive.

Trois garde-fous, tous mesurés :

- **rien n'est fatal.** Un paquet manquant, un `apt` en échec, un `apt-get update` sans
  réseau : l'application est posée et le manque est **dit**. Une Marionnet installée à côté
  d'une bibliothèque absente est à un `apt install` de démarrer ; un `install.sh` qui meurt
  au milieu laisse un arbre à moitié posé.
- **l'étape sudoers s'efface quand `visudo` n'est pas là.** `sudo` est *dans* la liste, et
  `bin/scripts/marionnet-sudoers.sh` valide sa règle par `visudo -cf` (l. 427) : sur une
  machine dénudée, sans cette garde, `install.sh` mourait en parlant de `visudo` au lieu de
  parler de ses dépendances. La garde interroge **`command -v visudo`**, pas la liste des
  manquants — sinon `--no-deps` (qui vide cette liste par construction) aurait rendu fatale
  une étape qui ne l'est pas. **Défaut trouvé par le banc**, exactement là.
- **le dernier mot est un avertissement** : quand il reste des paquets manquants, le
  « Try: … --help » final est suivi de « pas avant que ces N paquets soient là », parce que
  `libgtksourceview-3.0-1` absent ⇒ le binaire ne démarre pas du tout (épisode 9b).

### Le passe-plat, et son troisième état

`bin/scripts/marionnet-install.sh --binary` relaie `--with-deps` / `--no-deps` comme il
relaie déjà `--force`, `--no-sudoers` et `--no-config`. Son état interne a **trois** valeurs
(`ask` par défaut) et non deux : par défaut il ne transmet **rien**, et `install.sh` garde
son propre défaut. Un relais qui transformerait le défaut en option explicite déciderait en
silence à la place de l'utilisateur — c'est ce que le cas (e bis) du banc réseau mesure.

### Prouvé

- Banc `Makefile.d/release.binary.sh.bench/` : **27 → 39 cas**, tous verts, `rc 0`, sur le
  vrai tarball `marionnet_trunk-r908_amd64_glibc2.39.tar.xz`. Une **3ᵉ boîte** entre en
  scène : `debian:trixie-slim` **nue**, sans un seul paquet du runtime, qui reçoit le
  tarball **déjà déplié depuis l'hôte** — une machine sans `xz-utils` ne peut pas ouvrir un
  `.tar.xz`, et c'est précisément la machine qu'elle représente (le dépli, lui, est mesuré
  où il faut, cas 1). Une **4ᵉ**, la même mais **avec réseau**, joue `--with-deps` pour de
  bon : les 13 paquets arrivent, le binaire démarre, et la règle sudoers est posée dans la
  même exécution — la chaîne 9a → 10 d'un seul geste.
- **Discriminance : 10 cas rouges** contre l'artefact d'avant (`…-r906`), qui reste vert sur
  les 27 cas de l'épisode 9b (non-régression). Les cas de la section 10 sont tolérants aux
  échecs (`|| true`, capture du `rc`) : mesuré, sans cela un `install.sh` d'avant faisait
  **avorter** le banc sous `set -e` au lieu de le faire virer au rouge, ce qui se lit comme
  un défaut du banc.
- Banc réseau `bin/scripts/marionnet-install.sh.bench/` : **50 → 53 cas**, tous verts —
  les deux options atteignent l'`install.sh` embarqué, et **aucune** n'est transmise quand
  rien n'est demandé.

### Restes

- Inchangés : le repli `curl` (ép. 6), la complétion bash (§ 2.4 ter), la **signature** des
  artefacts, l'étape 1 (dépôt sur le serveur) et la jambe **https**, bloquées par
  l'extérieur.
- Ce que cet épisode ne fait **pas**, et laisse à l'enfant `…-par-script` : les dépendances
  d'une installation **par les sources** (`REQUIRED_PACKAGES_BUILD`, opam), et le cas
  non-Debian, où `install.sh` se contente d'afficher les noms Debian « ou leur équivalent
  local ».

## Épisode 11 (2026-08-31) — les deux derniers restes locaux de la consommation

Étape (1) de la feuille de route du § 5 bis. Deux choses que le chantier traînait depuis
l'épisode 6, sans rapport l'une avec l'autre sinon qu'elles se jouent **sans serveur** :
la complétion bash n'était installée nulle part, et l'installeur **exigeait `wget`**.

### 11a — la complétion bash trouve sa place, et c'est douze fichiers

`bin/dune` portait, depuis le chantier `move-and-rename-useful-scripts-to-bin-scripts`, un
commentaire disant que `scripts/marionnet-completion.bash` n'était **délibérément pas**
installée et que choisir sa destination revenait à ce chantier-ci. C'est fait.

**Où** : `$(PREFIX)/share/bash-completion/completions/`, donc une **seconde stanza
`install`** en section `share_root` (la section `share` est `$(PREFIX)/share/marionnet/`,
et ce répertoire-là n'appartient pas à Marionnet). Pas `/etc/bash_completion.d/` : c'est le
mécanisme *legacy*, tout y est sourcé par **chaque** shell, et il est cloué à `/etc` — donc
il ne suivrait pas un préfixe relogé, ce qui est exactement ce que le tarball de l'ép. 9a a
rendu possible.

**Combien** : **douze**, et la répétition est le fond de l'affaire, pas une maladresse.
`bash-completion` charge **à la demande**, en cherchant un fichier *portant le nom de la
commande tapée*. Les trois `complete -F` du pied de `marionnet-completion.bash` couvrent
douze noms (`marionnet-ctl.sh`, `marionnet-ctl`, `mrnctl`, `mrn-control`,
`marionnet-check.sh`, `marionnet-check`, `mrn-check`, `mrnck`, `mrn2sh`,
`marionnet-verify.sh`, `marionnet-verify`, `mrn-verify`) : installé sous un seul, il
complèterait `marionnet-ctl` et laisserait tous les autres **muets** tant que le premier
n'aurait pas été tapé dans le même shell. Douze destinations pour une source unique
(`(… as bash-completion/completions/<nom>)`) : déclaratif, sans logique, et valable pour
**tous** les canaux — `dune install`, le tarball, le futur `.deb` — au lieu d'une étape de
liens que chacun aurait à refaire. Coût : ~180 Kio.

**Ce qui aurait pu casser et ne casse pas** : la complétion cherche le client *à côté
d'elle-même*, et elle quitte `bin/scripts/`. `_mrn_ctl_program` a **trois** branches —
`$MARIONNET_CTL`, à côté de soi, puis le **PATH** ; c'est la troisième qui sert une fois
installé (les clients sont dans `$(PREFIX)/bin/`), la deuxième restant ce qui fait marcher
la complétion **depuis l'arbre source, sans rien installer**.

**Prouvé** : banc `Makefile.d/release.binary.sh.bench/` **39 → 42 cas**, tous verts sur le
tarball `r909` ; **3 rouges** sur le `r908` (l'artefact d'avant). Le cas qui compte est le
deuxième : *sourcer* `…/completions/mrnctl` doit armer `complete` **pour `mrnctl`**, pas
seulement pour `marionnet-ctl`. Le troisième a dû être corrigé pour valoir quelque chose :
`find` sur un répertoire absent n'écrit **rien** sur stdout, donc le cas « les fichiers
appartiennent à root:root » passait au vert sur une installation qui n'en posait aucun.

### 11b — le repli `curl`, et pourquoi `-f` n'est pas une commodité

Toute la surface HTTP de `bin/scripts/marionnet-install.sh` tient en **quatre** appels,
qui se réduisent à **deux verbes** : un **corps** (`catalog_list`, `artifact_stream`,
`sums_read`) et un jeu d'**en-têtes** (`artifact_size`). D'où `http_body` / `http_headers`,
et un `FETCHER` choisi **une fois** quand la source s'avère être une URL. `wget` reste
**premier** : c'est avec lui que tout a été mesuré jusqu'ici.

**`-f` est ce qui rend le repli équivalent, pas ce qui le rend agréable.** Sans lui, `curl`
sort **0** sur un 404 et écrit la page d'erreur du serveur sur stdout. `sums_read` y
survivrait — il **compte** les lignes qu'il reconnaît, garde posée à l'ép. 8 précisément
parce qu'un « 200 avec un corps HTML » existe — mais `artifact_stream` déverserait cette
page dans un tarball, et il ne resterait plus que le digest entre elle et le disque.
`wget -q -O -` échoue de lui-même sur un 404.

**Et pas de `-S`**, par la raison symétrique : `wget -q` ne dit **rien** quand il échoue, et
**l'un** de ces fetchs est censé échouer sur une release bien formée d'avant l'ép. 8 — le
`SHA256SUMS` absent, dont le script se remet en retombant sur le listing. Avec `-S`, `curl`
écrivait `curl: (22) … 404` au milieu d'un run qui se passait parfaitement (mesuré au banc).
Le silence ne perd rien : chaque appelant lit le **code de retour**, et le message que
l'utilisateur reçoit est celui du script.

**Prouvé** : banc `bin/scripts/marionnet-install.sh.bench/` **53 → 63 cas**, tous verts ;
**6 rouges** sur le script d'avant l'épisode. La deuxième image cliente
(`Dockerfile.client.curl`) porte `curl` **et pas** `wget` — une image portant les deux ne
prouverait rien, `wget` étant choisi en premier — et la boîte « ni l'un ni l'autre » est un
`debian:trixie-slim` **brut**, qui vérifie que la garde nomme bien **les deux**. Les deux
cas de fond : le **403** de `kernels_linux-locked.tar.xz` doit arrêter le run *et* ne rien
laisser sous ce nom (le `-f`), et aucune ligne `curl:` ne doit subsister dans la sortie d'un
run nominal (l'absence de `-S`).

### Restes

- Inchangés, et toujours **bloqués par l'extérieur** : le dépôt sur le serveur (§ 5 bis,
  point 5), la jambe **https**, la **signature** des artefacts.
- Le banc ne connaît toujours qu'une seule distribution : c'est le point (2) de la feuille
  de route, l'épisode suivant.


## Épisode 12 (2026-08-31) — les quatre boîtes

Point (2) de la feuille de route du § 5 bis. Jusqu'ici les deux bancs ne connaissaient
qu'une `debian:trixie-slim` : tout ce que les épisodes 6 à 11 ont mesuré l'avait été sur
**une seule** distribution, alors que Marionnet s'installe sur au moins quatre. La boîte
devient donc un **paramètre** — `--distro <image>`, ou `--distro all` qui rejoue le banc sur
les quatre et ne rend qu'un code de sortie (le pire, un SKIP ne masquant jamais un FAIL).

Le défaut reste `debian:trixie-slim` dans les deux bancs et dans les trois `Dockerfile` :
**un run sans argument veut dire ce qu'il a toujours voulu dire**, ce qui est la condition
pour que les mesures des épisodes précédents restent comparables.

### Ce qui a coûté presque rien, et pourquoi

Le banc **réseau** n'a demandé que l'`ARG BASE_IMAGE` de ses deux images clientes. La raison
est une décision de l'**épisode 9c** : l'arch et la glibc des artefacts synthétiques sont
demandées au **conteneur client**, jamais à l'hôte du banc. Toute la famille de cas
`--binary` — l'élu, le supplanté, l'arch étrangère, la glibc trop récente — suit donc la
boîte d'elle-même. **63 verts sur chacune des quatre**, sans un cas à retoucher.

De même, les **13 `REQUIRED_PACKAGES_RUNTIME`** existent, sous ce nom, sur les quatre : le
pari fait à l'épisode 9b (nommer `libgtksourceview-3.0-1` plutôt que `libgtk-3-0`, dont le
nom a pris un `t64` en trixie et en noble mais pas en bookworm) tient — il est maintenant
mesuré et non plus raisonné.

### Debian 12 : le seul écart, et il n'est pas un défaut

L'artefact publiable est lié à la glibc de la machine qui l'a compilé (ici 2.39). Sur une
boîte **plus ancienne**, il ne peut pas démarrer : la garantie de versionnement de symboles
de la glibc ne vaut que dans un sens. Le banc binaire lit donc l'arch et la glibc **dans le
nom du tarball**, exactement comme `marionnet-install.sh` le fait pour choisir, et en tire
trois conséquences :

- il ne saute **pas** le run. Poser les fichiers, écrire la configuration, poser la règle
  sudoers, installer la complétion et nommer les dépendances apt se mesurent tout aussi bien
  sur une boîte trop ancienne — et ce sont justement les gestes qui changent d'une
  distribution à l'autre ;
- seuls les **quatre cas qui démarrent le binaire** s'effacent (SKIP), et **un cas neuf prend
  leur place** : le refus doit **nommer la glibc**. C'est ce qui transforme le critère lu
  dans le nom en fait mesuré plutôt qu'en décoration — et son symétrique est mesuré aussi,
  Ubuntu 26.04 (glibc 2.43) faisant tourner sans broncher un binaire lié contre 2.39 ;
- une **architecture** étrangère, elle, fait sauter tout le run (77) : il n'y aurait
  strictement rien à mesurer.

**Ce qu'il faut en retenir pour la suite : pour servir Debian 12, il faudra construire sur
Debian 12.** Une matrice de compilation est un autre travail — elle n'entre pas dans cet
épisode, dont le rôle était de faire dire au banc, sans se mentir, que l'artefact courant
n'est pas pour cette boîte-là.

### Le cas neuf, et le piège qu'il a fallu payer pour qu'il vaille quelque chose

L'épisode 11a avait prouvé que **sourcer** un des douze fichiers de complétion arme
`complete` pour ce nom-là. Il n'avait pas prouvé le geste que l'utilisateur fait vraiment :
taper `mrnctl <TAB>` dans un shell qui n'a rien sourcé. `bash-completion` charge **à la
demande**, en cherchant un fichier portant le nom de la commande sous
`${XDG_DATA_DIRS:-/usr/local/share:/usr/share}/bash-completion/completions` — et la présence
de `/usr/local/share` dans ce défaut est typiquement ce qui pourrait différer d'une
distribution à l'autre. D'où un 43ᵉ cas, joué sur une **boîte à part** (avec réseau, portant
le seul paquet `bash-completion`, qui n'est pas une dépendance de Marionnet et n'a rien à
faire dans l'image cliente).

**Piège durable, mesuré ici** : le chargeur de `bash-completion` retombe sur
`complete -o default -F _minimal` pour une commande qu'il ne connaît pas. Un cas qui se
contente de `complete -p mrnctl` **passe donc au vert sur une boîte où rien n'a été
installé**. Le cas vérifie le **nom de la fonction armée** (`_marionnet_ctl_completion`) ;
contre-preuve jouée : rc 1 sans installation, rc 0 avec.

### Prouvé (2026-08-31)

| Banc | `debian:bookworm-slim` | `debian:trixie-slim` | `ubuntu:24.04` | `ubuntu:26.04` |
|---|---|---|---|---|
| `Makefile.d/release.binary.sh.bench/` (43 cas) | 39 verts, **4 sautés** | 43 verts | 43 verts | 43 verts |
| `bin/scripts/marionnet-install.sh.bench/` (63 cas) | 63 verts | 63 verts | 63 verts | 63 verts |

glibc des boîtes : 2.36 / 2.41 / 2.39 / 2.43 ; artefact mesuré : `marionnet_trunk-r909_amd64_glibc2.39`.

### Restes

- **Les quatre boîtes sont soldées** ; la suite est le point (3), le découpage en `.deb`.
- Une **matrice de compilation** (un artefact par glibc visée, à commencer par Debian 12)
  n'est pas spécifiée : elle n'est pas un reste de cet épisode mais une question ouverte, à
  formuler quand le `.deb` aura dit ce qu'il prend en charge.
- Inchangés, et toujours **bloqués par l'extérieur** : le dépôt sur le serveur, la jambe
  **https**, la **signature** des artefacts.

## Épisode 13 (2026-08-31) — combien de `.deb`

Point (3) de la feuille de route § 5 bis. **Épisode sans code** : il ne fabrique rien, il
**tranche** — la décision « app + noyaux + petites images en `.deb`, grosses images à part »
du § 6 datait du 2026-07-19, c'est-à-dire d'avant que l'application soit un artefact et avant
que ses dépendances soient une donnée. Elle est ici rejugée sur des mesures, et elle **tient**,
mais son découpage se précise et deux de ses trois motifs ont changé.

### Ce qu'on empaquette, mesuré et non supposé

| Ce qui serait empaqueté | Compressé | Déplié | Remarque |
|---|---|---|---|
| l'application (staging `dune install` + les 15 noms de `bin/scripts/`) | 7,4 Mio | **32,8 Mio**, 372 entrées | `marionnet_trunk-r909_amd64_glibc2.39.tar.xz` |
| `doc-src/` (guides livrés) | — | 2,1 Mio (1,4 sans les PDF) | **n'est installé par aucun canal** (§ 2.4 ter) |
| noyau `linux-6.12.95` | 2,8 Mio | 8,1 Mio | ELF **x86-64**, `NEEDED` = `libc.so.6` |
| noyau `linux-6.12.95-i386` | 2,2 Mio | 5,2 Mio | ELF **i386**, `NEEDED` = `libc.so.6` + `/lib/ld-linux.so.2` |
| image `guignol` (machine **et** routeur) | 12,6 Mio + 3,8 Kio | 55 Mio | le routeur est un **lien** vers la machine |
| image `wheezy` | 423 Mio | **1,8 Gio** | |
| image `trixie` | 1,09 Gio | **5,1 Gio** | |

### La décision : quatre paquets, et pourquoi ce ne sont pas les quatre du RPM

```
marionnet              amd64  ~35 Mio  le binaire, les 15 noms, la complétion ×12,
                                       share/marionnet/{share,images,scripts,locale},
                                       /etc/marionnet/marionnet.conf (conffile), les guides
marionnet-kernels      amd64  ~8 Mio   linux-6.12.95 (+ .config)
marionnet-kernels-i386 amd64  ~5 Mio   linux-6.12.95-i386, pour les vieux couples
marionnet-fs-guignol   all    ~55 Mio  machine ET routeur guignol
```

et **rien d'autre dans apt** : `wheezy` et `trixie` restent des artefacts de release, tirés
par `marionnet-install.sh`.

Le précédent RPM (`RPMS/`, 2009) découpait autrement : `marionnet-common`,
`marionnet-kernels-default`, `marionnet-fs-machines-default` **et**
`marionnet-fs-routers-default`. Ce quatrième paquet n'a plus d'objet, et son propre
changelog dit pourquoi : *« 2009-11-08 : rename router → routers, **added symlinks** »*.
Un artefact routeur d'aujourd'hui pèse **3,8 Kio** et ne contient qu'un lien symbolique
vers l'image machine, son `.conf` et un répertoire de variantes vide. Un paquet séparé
porterait donc un **lien pendant** tant que son voisin n'est pas installé — un `Depends:`
strict entre deux paquets dont l'un est vide n'est pas un découpage, c'est une jointure.
D'où : **une image, un paquet, machine et routeur ensemble**.

Les deux noyaux, en revanche, se séparent — et c'est le seul endroit où la séparation
paye. Le noyau i386 est un ELF 32 bits dont l'**interpréteur est écrit en dur dans le
binaire** : `/lib/ld-linux.so.2` (mesuré). Or, sur cette machine (Ubuntu 24.04), le paquet
`libc6-i386` — le runtime 32 bits « natif » d'un système amd64 — ne fournit **que**
`/usr/lib32/ld-linux.so.2` et un fichier `ld.so.conf.d` ; c'est **`libc6:i386`**, donc
l'architecture étrangère, qui possède `/lib/ld-linux.so.2`. Autrement dit : la dépendance
*bon marché* (`libc6-i386`, sans `dpkg --add-architecture`) **n'est pas établie**, et la
dépendance sûre reste celle que `REQUIRED_PACKAGES_RUNTIME_I386` du `Makefile` nomme déjà
pour l'installation par les sources — `libc6:i386`, qui **impose d'activer une architecture
étrangère** sur la machine de l'utilisateur.

Ce qui, loin d'affaiblir la séparation, la **justifie** : un paquet capable de faire
activer une architecture étrangère à apt est exactement ce qu'on ne veut pas imposer à
tout le monde pour une fonction de **rétro-compatibilité** dont la plupart des
installations n'useront jamais. `marionnet-kernels-i386` est donc le seul des quatre à
porter cette dépendance — **et sa forme exacte (`libc6-i386` suffit-il sur telle boîte ?
sinon `libc6:i386`) est à MESURER sur les quatre boîtes au point (4)** : c'est la seule
dépendance du découpage qui ne se dérive pas de la source de vérité du `Makefile`.

Enfin les guides restent **dans** `marionnet`, sans paquet `-doc` : 2,1 Mio ne justifient
pas la scission que la politique Debian réserve aux grosses documentations, et une
documentation d'usage séparée de l'outil qu'elle documente est exactement le défaut que
le § 2.4 ter reproche à l'état actuel. **Note d'ordonnancement** : `doc-src/` n'étant
installé par *aucun* canal aujourd'hui, ce n'est pas au `.deb` de le réparer — c'est à la
stanza `install` de `bin/dune`, d'où tous les canaux le recevront (tarball compris).
C'est un épisode à part, à jouer **avant** le point (4).

### Ce qui a changé depuis le § 6 : `Depends:` se dérive, il ne se recopie pas

La liste des dépendances d'exécution est **déjà une donnée générée** — épisode 10,
`REQUIRED-PACKAGES-RUNTIME`, tirée de `REQUIRED_PACKAGES_RUNTIME` du `Makefile`. Le
`Depends:` du paquet `marionnet` s'en dérive donc, et l'y recopier recréerait la seconde
source de vérité que l'épisode 1 a supprimée.

Mieux : la mesure montre que cette liste de 13 se coupe proprement en deux, et que la
coupure a un sens précis — **ce que `ldd` voit** contre **ce que seul le `Makefile`
sait** :

- une seule entrée est une **bibliothèque** (`libgtksourceview-3.0-1`) : `dpkg-shlibdeps`
  la retrouverait tout seul, avec ses 12 sœurs GTK et, surtout, avec la borne
  `libc6 (>= 2.39)` ;
- les **douze autres** (`vde2 graphviz uml-utilities xterm iproute2 sudo x11-xserver-utils
  xauth jq socat dnsmasq-base xz-utils`) sont des **commandes appelées par leur nom** depuis
  l'OCaml et depuis les scripts de `bin/scripts/`. Aucun outil automatique ne peut les
  trouver : c'est précisément pourquoi le `Makefile` en est la source de vérité.

D'où la forme retenue : `Depends: ${shlibs:Depends}, ` + la liste générée **entière**,
sans filtrage à la main (dpkg dédoublonne ; retirer `libgtksourceview-3.0-1` parce que
`shlibdeps` le trouve serait un tri à maintenir, donc une seconde vérité en germe).

**Conséquence heureuse, à noter** : la contrainte glibc que l'épisode 12 a dû écrire
**dans le nom du tarball** (`…_glibc2.39.tar.xz`, faute de pouvoir l'exprimer autrement)
devient ici une **métadonnée** — `libc6 (>= 2.39)`, posée par `shlibdeps`, qu'apt sait
faire respecter. Le `.deb` ne supprime pas le fait qu'un binaire construit ici ne tourne
pas sur Debian 12 ; il le rend **refusable par l'outil** au lieu d'être lisible dans un
nom de fichier.

### Le préfixe : `/usr`, et le **même** binaire que le tarball

Le paquet installe sous `/usr` et pose `/etc/marionnet/marionnet.conf` en **conffile**,
pointant `MARIONNET_PREFIX=/usr/share/marionnet`. C'est le mécanisme déjà prouvé à
l'épisode 9b, et il permet de **ne compiler qu'une fois** : le `.deb` se fabrique du même
staging que le tarball, dont le préfixe compilé (`/usr/local`, via `CONFIGME`) n'est
qu'un défaut que la cascade de `bin/configuration.ml` recouvre.

L'alternative — recompiler avec `CONFIGME` fixé à `/usr` — évite le conffile mais coûte
une seconde compilation par release et un second artefact à cataloguer et à éprouver, pour
supprimer un fichier dont l'épisode 9a a justement établi qu'il fallait l'écrire *même
quand il ne fait que redire le défaut*, « un fichier qui n'existe que dans le cas
inhabituel étant un fichier dont personne ne se souvient quand ça va mal ».

**Interaction à ne pas découvrir sur le terrain** : sur une machine où le tarball est déjà
passé, ce fichier existe et n'appartient à personne ; dpkg le verra comme un conffile
modifié localement et posera la question à l'installation. C'est le comportement voulu (on
ne piétine pas la configuration de l'utilisateur), mais il doit être **mesuré** au point (4).

### La règle sudoers : le postinst **nomme**, il n'accorde pas

Symétrique exact de ce que l'épisode 10 a décidé pour les dépendances apt. Le tarball
habilite `$SUDO_USER` parce qu'un humain vient de lancer `sudo ./install.sh` : la question
« pour qui ? » a une réponse. Un paquet, lui, ne l'a pas — `apt install` peut venir d'un
outil d'automatisation, d'une image de conteneur, d'un `unattended-upgrade`. Le postinst
**imprime** donc la commande (`marionnet-sudoers.sh install <user>`) et n'accorde rien.

Écarté : `debconf`, qui saurait poser la question — mais ajoute une dépendance, un
template à traduire ×12, et ne répond toujours rien en mode non interactif.
Écarté aussi : habiliter `$SUDO_USER` comme le tarball — cela accorde **en silence** des
privilèges à un utilisateur **deviné**, ce qui n'est pas ce qu'on a demandé au paquet.

### Où les paquets sont publiés, et le seul piège de ce choix

Ils sont déposés dans le **répertoire de release de la série** —
`download/marionnet-install.sh/1.0.x/` — comme le binaire de l'épisode 9a, et pour la même
raison : une release dit ce qu'elle contient en **un** endroit. apt sait consommer un tel
répertoire, sous la forme d'un *flat repository* :

```
deb [signed-by=/usr/share/keyrings/marionnet.gpg] https://www.marionnet.org/download/marionnet-install.sh/1.0.x/ ./
```

Trois choses en découlent, et il vaut mieux les écrire maintenant :

1. **Deux catalogues cohabiteront dans ce répertoire**, et ils n'ont pas le même
   propriétaire : `SHA256SUMS` (le nôtre, écrit par `Makefile.d/release.sha256sums.sh`, seul
   écrivain — épisode 8) et `Packages`/`Release` (ceux d'apt, qu'un cinquième outil de
   publication devra écrire). Ce n'est pas la divergence que l'épisode 8 redoutait — ils
   décrivent le même répertoire, chacun pour son consommateur — mais la règle « un artefact
   déposé sans passer par le catalogueur est invisible » vaut désormais **deux fois**.
2. **La version d'un paquet n'encode PAS la série.** « Relatif à la série » veut dire *publié
   sous le répertoire de la série*, jamais *versionné par elle* : un noyau se versionne
   `6.12.95`, une image `18474`, et seul `marionnet` porte la version de l'application.
   Sinon l'ouverture d'une série `1.1.x` forcerait à reconstruire des paquets dont le contenu
   n'a pas bougé — et à en changer la version sans que rien n'ait changé, ce qu'apt
   présenterait à l'utilisateur comme une mise à jour.
3. **La ligne `sources.list` est épinglée sur la série**, donc l'ouverture de `1.1.x`
   demanderait de l'éditer sur chaque machine. Correctif à prévoir au point (5) : exposer
   `download/apt/` comme **point d'entrée stable** (lien ou `Alias` Apache) vers la série
   courante, et n'écrire *que* celui-là dans la documentation.

### Comment ils seront fabriqués (point (4), pas ici)

Pas de paquet source, pas de `dpkg-buildpackage` : l'inclusion dans Debian officielle est
**hors périmètre** depuis le § 6, et une construction depuis les sources exigerait opam et
camlp4 dans un chroot de build. Le `.deb` sera **binaire**, assemblé du staging que
`Makefile.d/release.binary.sh` produit déjà — un cinquième membre de la famille des
publieurs (`filesystem.prepare-snapshot-to-publish.sh`, `kernel.prepare-to-publish.sh`,
`release.binary.sh`, `release.sha256sums.sh`), qui appellera le catalogueur comme les
autres.

**Invariant à porter dans cette fabrication** : le `mtime` d'une image invitée est ce
qu'UML vérifie, et les deux canaux doivent livrer **le même**. dpkg conserve les `mtime`
de `data.tar` ; encore faut-il que le paquet les prenne de l'artefact publié et non de
l'instant de la construction, sans quoi un projet fait avec l'image du tarball refuserait
de s'ouvrir sur une machine où elle vient d'apt.

### Le creusement des images : mesuré, et **non retenu**

Question posée en séance : y a-t-il de la place à gagner en rendant `trixie` creux ?
**Non, il n'y a pas de gain à prendre** — et c'est mesuré :

| Image | Taille | Zéros (blocs 4 Kio) | Blocs libres (`dumpe2fs`) |
|---|---|---|---|
| `machine-debian-trixie-39212` | 5,01 Gio | 0,40 Gio (**8,0 %**) | 137 107 × 4 Kio = **0,52 Gio** |
| `machine-debian-wheezy-08367` | 1,78 Gio | 0,26 Gio (14,7 %) | 66 511 × 4 Kio = 0,25 Gio |
| `machine-guignol-18474` | 0,05 Gio | 0 | 8 161 × 1 Kio = 0,008 Gio |

L'image `trixie` est **pleine à 90 %** : le plafond théorique du creusement est ses 0,52 Gio
d'espace libre, dont 0,40 Gio sont **déjà** des zéros. Le gain réel plafonne donc à ~2 % de
plus que ce qu'un `tar -S` capterait tout seul, et il ne porte que sur le **disque de la
machine cible** — en transit, `xz` efface déjà ces zéros (5,01 Gio → 1,09 Gio). En face, le
prix : passer `-S` de bout en bout dans la chaîne de publication (aucun des trois scripts ne
le fait aujourd'hui) et, pour creuser un artefact **déjà publié**, le recopier — donc lui
donner un **`mtime` neuf**, c'est-à-dire toucher à la discipline la plus coûteuse du
chantier, celle qui décide si les projets existants s'ouvrent encore. Le rapport est
défavorable ; c'est classé **hors périmètre**, avec le chiffre qui le justifie.

### Restes

- Le point (3) est soldé. La suite est le point (4) — écrire les quatre paquets et les
  éprouver sur les quatre boîtes — **précédé** de l'épisode « `doc-src/` s'installe », qui
  n'est pas un travail de `.deb` mais de `bin/dune`.
- Inchangés, et toujours **bloqués par l'extérieur** : le dépôt sur le serveur, la jambe
  **https**, la **signature** des artefacts — c'est elle qui décidera de la clef du dépôt
  apt (`signed-by=`), donc le point (5) et le dépôt apt se jouent ensemble.

## Épisode 14 (2026-08-31) — `doc-src/` s'installe

Point (3 bis) de la feuille de route § 5 bis, révélé par l'épisode 13 : en dressant la liste
de ce que le paquet `marionnet` devrait porter, on a constaté que les guides — 2,1 Mio écrits
**pour qui n'a pas le dépôt** — n'étaient posés par **aucun** canal. Le constat lui-même est
plus ancien (§ 2.4 ter, 2026-08-13) ; ce qui a changé, c'est qu'il devenait la dernière
raison de ne pas commencer les `.deb`.

Ce n'est pas un travail de `.deb`. Un paquet qui installerait une documentation que
`dune install` ne connaît pas ferait exactement ce que l'épisode 1 a supprimé ailleurs : une
seconde source de vérité. La réparation est donc **un fichier `doc-src/dune`**, et tous les
canaux la reçoivent d'un coup — `dune install --prefix`, le tarball de l'épisode 9a, et le
`.deb` à venir, qui est assemblé du même staging.

### La destination, et pourquoi ce n'est pas la section `doc` de dune

`$(PREFIX)/share/doc/marionnet/` — ce que la FHS, Debian et un lecteur attendent. La section
`doc` de dune installe sous `$(PREFIX)/doc/<paquet>`, ce qui donnerait `/usr/doc/marionnet`
sur la machine servie par apt. On reprend donc le procédé de la complétion (épisode 11a) :
section **`share_root`** avec un `as doc/marionnet/…` explicite, la seule façon d'atteindre un
répertoire qui n'appartient pas au paquet.

**Chaque fichier est nommé un par un**, comme le fait `bin/dune`. C'est ce qui garde dehors
les sources du manuel texinfo historique (`documentation.texi`, `macros.texi`, `epsf.tex`,
`img/`, `img-src/`, `NETWORK-SIMULATION`) — elles ne sont pas la documentation d'usage — et,
tout aussi important, ce qui garde dehors les fichiers **présents ici mais absents de git**
(la traduction française du guide de l'enseignant et ses rendus PDF, travaux en cours) :
nommer dans un `dune` un fichier que dune ne trouve pas **casse le build sur un clone frais**.

26 fichiers : 4 documents à la racine, le guide du canal et ses 10 exemples, le TP complet
`labs/session-7/` et ses 10 fichiers.

### L'arborescence est conservée, donc les citations devaient changer

Ces documents **se citent les uns les autres par chemin** — c'est le mécanisme qui remplace
la recopie d'un guide dans un autre, et c'est aussi ce qui fait qu'un agent à qui le guide de
l'enseignant dit « lis `lab-design-skill.md` et suis-le » trouve le fichier. Or ils étaient
écrits `doc-src/…`, c'est-à-dire **relatifs à la racine d'un clone** : une machine servie par
apt n'a aucune raison de posséder ce chemin.

Les 61 occurrences sont donc devenues **relatives au répertoire qui contient le document**.
Une seule règle, et elle est vraie **aux deux endroits** : dans le dépôt (le lecteur est dans
`doc-src/`) comme sur la machine installée (il est dans `share/doc/marionnet/`). Trois
documents d'entrée l'énoncent en une phrase, parce qu'un chemin relatif ne dit pas tout seul
à quoi il est relatif — et cette phrase est le seul endroit où `doc-src/` reste écrit, comme
*nom de son emplacement dans les sources*. Les exemples shell du § 5 du guide de l'enseignant
se jouent donc depuis ce répertoire, ce que la phrase dit aussi.

### Le bit exécutable, que `dune` ne sait pas porter

**Mesuré** : `dune install` pose tout ce qui n'est pas de la section `bin`/`libexec` en
**0644** — un `(files (x.sh as …))` en section `share_root` arrive non exécutable. Ce n'est
pas neuf, c'est exactement pourquoi le `Makefile` fait déjà `chmod +x` sur
`share/marionnet/scripts/` après `dune install` ; mais ici cela mordait pour de bon, un TP
qu'il faut `chmod` avant de le jouer n'étant plus « rejouable tel quel ».

Chaque canal restaure donc le bit juste après dune : les **deux** cibles d'installation du
`Makefile` (`install-final-as-root` via son script root, `install-for-testing`) et
`Makefile.d/release.binary.sh`, qui prépare le staging — donc, à travers lui, le `.deb` à
venir. La règle appliquée est **uniforme** — tout `*.sh` des deux répertoires d'exemples —
plutôt qu'une liste, qui serait une seconde source de vérité pour une propriété que les
fichiers portent déjà dans le dépôt. Elle accorde **un bit de plus** que le dépôt, à
`scripting/examples/scenario-ping.sh`, dont la première ligne dit qu'il n'est de toute façon
pas exécuté sur l'hôte.

### Prouvé (2026-08-31)

Banc `Makefile.d/release.binary.sh.bench/` : **43 → 48 cas**, cinq neufs sur la
documentation livrée — les 26 fichiers présents, l'arborescence conservée (9 chemins cités
vérifiés là où les documents les nomment), les 14 scripts exécutables et les documents qui ne
le sont pas, **aucun renvoi résiduel** vers `doc-src/<document>`, et `root:root`.

- **48 verts** sur `debian:trixie-slim`, sur le tarball fabriqué par `make release-binary`
  (`marionnet_trunk-r912_amd64_glibc2.39`, 7,2 Mio) ;
- **discriminance mesurée** : rejoué sur l'artefact d'avant (r909), **5 rouges sur 5**.
- `--distro all` : **44 verts + 4 sautés** sur `debian:bookworm-slim` (la boîte dont la
  glibc est trop ancienne pour démarrer le binaire — les cinq cas neufs, eux, s'y jouent) et
  **48 verts** sur `debian:trixie-slim`, `ubuntu:24.04` et `ubuntu:26.04`.

**Piège payé ici, et c'est celui de l'épisode 12 sous un autre visage** : trois des cinq cas
*cherchent* quelque chose (`find`, `grep`) et **ne trouvent rien quand le répertoire n'existe
pas** — deux d'entre eux passaient donc au vert sur l'arbre même qu'ils devaient condamner.
Ils sont désormais **gardés sur l'existence du répertoire** (`test -d … || echo
NO-SUCH-DIRECTORY`), procédé déjà utilisé par le cas de propriété de la complétion.

### Restes

- La documentation **n'est toujours pas mesurée par le banc réseau**
  (`bin/scripts/marionnet-install.sh.bench/`), et ce n'est pas un oubli : ce banc mesure
  le **relais** (`marionnet-install.sh --binary` déplie l'artefact et lance l'`install.sh`
  qui voyage dedans), lequel est déjà éprouvé sur les 63 cas existants ; ce que la
  documentation exige en propre est mesuré là où elle est produite.
- Le point (4) — écrire les quatre `.deb` et les éprouver sur les quatre boîtes — n'a plus
  d'obstacle : le paquet `marionnet` peut porter les guides parce qu'ils sont, enfin, dans le
  staging que `release.binary.sh` produit.

## Épisode 15a (2026-08-31) — les quatre `.deb` existent

Point (4) de la feuille de route, **premier temps** : les fabriquer et les contrôler
localement. Le second temps (15b) est de les **installer** sur les quatre boîtes, avec le
dépôt apt à plat, et c'est là que se mesurera la seule dépendance que l'épisode 13 a laissée
ouverte.

Un fichier neuf, `Makefile.d/release.deb.sh` (cible `make release-deb`, `PACKAGES="app
kernels"` pour n'en faire qu'une partie), **cinquième membre de la famille des publieurs** :
il écrit dans le **même** répertoire de release que les quatre autres et s'inscrit dans le
**même** `SHA256SUMS`.

### Ce qu'il assemble, et de quoi

| paquet | arch | taille | fait de |
|---|---|---|---|
| `marionnet` | amd64 | 7,2 Mio (33,7 Mio installés) | le **staging que `release.binary.sh` produit déjà** |
| `marionnet-kernels` | amd64 | 2,7 Mio | `kernels_linux-6.12.95.tar.xz`, **l'artefact publié** |
| `marionnet-kernels-i386` | amd64 | 2,1 Mio | `kernels_linux-6.12.95-i386.tar.xz` |
| `marionnet-fs-guignol` | all | 13 Mio | `filesystems_machine-guignol-18474.tar.xz` **et** `filesystems_router-guignol-18474.tar.xz` |

Rien n'est décrit deux fois. Pour l'application, ce script **appelle** `release.binary.sh
--staging-dir … --no-tarball` (option neuve, six lignes) au lieu de redire ce qu'est une
installation : les deux gestes que `dune install` ne fait pas — les scripts de `bin/scripts/`
vers `bin/`, le bit exécutable rendu aux exemples de la documentation — sont **déjà** dans ce
staging, et le jour où un troisième s'ajoutera, le `.deb` l'aura sans qu'on y pense. Pour les
données, il **déplie l'artefact publié**, ce qui est la seule façon de tenir l'invariant
ci-dessous.

Ce qui **n'entre pas** dans le paquet de l'application, des trois fichiers que le staging
porte à sa racine : `install.sh` (ici l'installeur, c'est dpkg), `README` (sa section INSTALL
décrit `install.sh`) et `REQUIRED-PACKAGES-RUNTIME` (la liste devient `Depends:`, c'est-à-dire
quelque chose sur quoi un gestionnaire de paquets peut agir). **Mesuré** : le `.deb` ne
contient aucun des trois, et contient bien les 24 noms de `bin/`, les 12 fichiers de
complétion et les 33 fichiers de documentation.

### L'invariant du `mtime`, tenu et mesuré

Le `mtime` d'une image invitée est ce qu'UML vérifie contre le `.conf` de son *backing
file* ; les deux canaux doivent donc livrer **le même**. D'où : les paquets de données sont
faits en dépliant le tarball publié (jamais `tar -m`, jamais une copie fraîche), et dpkg
conserve les `mtime` de `data.tar`. **Mesuré** — l'image guignol arrive dans le `.deb` datée
`2017-06-09 15:01`, exactement comme dans le tarball, et le lien symbolique
`router-guignol-18474 → machine-guignol-18474` avec elle, `root:root`.

### Les dépendances : dérivées deux fois, écrites nulle part

`Depends:` du paquet `marionnet` est l'union de deux sources, dont **aucune** n'est retapée :

- **ce que `ldd` voit** — demandé à `dpkg-shlibdeps`, qui lit les symboles réellement
  utilisés. C'est de là que vient `libc6 (>= 2.38)` : la contrainte que l'épisode 12 ne
  savait écrire que dans un **nom de fichier** (`_glibc2.39`) devient une **métadonnée** qu'apt
  sait refuser avec une phrase ;
- **ce que seul le `Makefile` sait** — les douze commandes appelées par leur nom nu
  (`vde_switch`, `dot`, `jq`, `socat`, `dnsmasq`, `xterm`…), qu'aucun éditeur de liens ne
  peut voir. `REQUIRED_PACKAGES_RUNTIME`, lu **à travers `make`**, en est la source de vérité
  unique depuis l'épisode 1.

Le seul nom commun aux deux (`libgtksourceview-3.0-1`, que l'épisode 9b avait ajouté à la
main pour une raison mesurée) est **retiré par un test sur le nom**, pas par un tri humain :
un fichier de contrôle qui dit deux fois la même chose est un fichier de contrôle dont
personne ne se sert.

Le noyau 64 bits y a droit aussi, et ce n'est pas de la symétrie décorative : c'est un ELF
dynamiquement lié (`ldd` nomme `libc.so.6`), et lintian dit `missing-dependency-on-libc` tant
que le `Depends:` se tait. Il porte donc `marionnet, libc6 (>= 2.38)`. Les deux autres
paquets de données ne dépendent que de `marionnet` — comme les paquets de données du RPM de
2009 dépendaient de `marionnet-common`.

### La version d'un paquet, et pourquoi elle commence par `0~`

**Mesuré** : `dpkg-deb` refuse `trunk-r906` (« le numéro de version ne commence pas par un
chiffre »), et `META` dit `trunk` aujourd'hui. D'où `0~trunk+r913`, dont chaque morceau
répond à quelque chose :

- `0~` fait comparer la version **plus bas que `1.0.0`** (vérifié avec `dpkg
  --compare-versions`) : le jour où `META` nomme une vraie version, apt voit tous les paquets
  de tronc comme des prédécesseurs à mettre à jour — ce qu'une pré-version est ;
- `+r913` plutôt que `-r913`, parce que `-` ouvre le champ *révision Debian*, alors que le
  compte de révisions git appartient à l'amont. Deux constructions de la même version restent
  ordonnées par l'histoire où elles ont été coupées (r906 < r913, vérifié) ;
- les paquets de données, eux, se versionnent par leur **contenu** — `6.12.95` pour un
  noyau, `18474` pour une image — lu **dans le nom de l'artefact**, jamais par la série
  (décision de l'épisode 13).

### Le postinst nomme la règle sudoers, il ne l'accorde pas

Comme décidé à l'épisode 13, et pour la raison de l'épisode 10 : `apt install` n'a pas de
réponse à « pour quel humain ? » — il peut venir d'une construction d'image ou d'une mise à
jour automatique. Le postinst **imprime** `sudo marionnet-sudoers.sh install <user>` et rappelle
que les blocs NAT/LAN se demandent depuis l'interface. Le `prerm`, symétriquement, **nomme**
la commande de retrait sans l'exécuter : ce paquet n'a rien accordé, il ne retire rien.

`/etc/marionnet/marionnet.conf` est un **conffile** déclaré, pointant `/usr/share/marionnet` :
c'est ce qui permet de ne compiler qu'une fois (le préfixe compilé, `/usr/local`, n'est qu'un
défaut que la cascade de `bin/configuration.ml` recouvre). Sur une machine où le **tarball**
est déjà passé, ce fichier existe et n'appartient à personne : dpkg y verra un conffile
modifié localement et posera la question. C'est voulu — et c'est l'un des cas à jouer en 15b.

### Ce que lintian dit, et les trois fois où on ne l'écoute pas

Il tourne sur chaque paquet (`--no-lintian` pour couper) et n'est **jamais** fatal : il juge
selon la politique de la distribution où il s'exécute, or ces paquets ne visent pas Debian
officielle (§ 6). Quatre de ses remarques ont été des **défauts réels**, corrigées : les
répertoires créés avec l'umask du packageur (0775 — un paquet ne doit pas rendre
`/usr/share` inscriptible par le groupe, d'où `umask 022`), le changelog nommé
`changelog.Debian.gz` alors que ces versions sans révision Debian font des paquets *natifs*,
deux descriptions dépassant 80 colonnes, et la dépendance libc du noyau ci-dessus. Trois
autres sont des **réponses**, gardées avec leur raison :

- `executable-in-usr-share-doc` — les quatre scripts d'exemple sont faits pour être **joués**
  par le lecteur ; leur rendre ce bit est précisément ce que l'épisode 14 a dû ajouter aux
  trois canaux ;
- `missing-depends-on-sensible-utils` — **mesuré** : `sensible-editor` est l'un de cinq
  **candidats** de `bin/treeview_documents.ml`, chacun testé avant usage (`xdg-open` d'abord).
  Lintian ne voit que la chaîne dans le binaire. Rien à ajouter à
  `REQUIRED_PACKAGES_RUNTIME` — contrairement à `xz-utils` et `libgtksourceview-3.0-1`, que
  l'épisode 9b y a mis parce qu'ils étaient appelés **sans repli** ;
- `unstripped-binary-or-object` — **mesuré** : `strip --strip-unneeded` fait passer le binaire
  de 27,6 à 18,2 Mio, et le binaire allégé démarre encore. Refusé quand même : le `.deb` et
  le tarball doivent livrer **le même binaire** (une seule compilation sert les deux canaux,
  épisode 13), et un canal qui *strippe* est un canal dont les rapports de bug ne portent pas
  les mêmes traces que l'autre.

Reste `arch-dependent-file-in-usr-share` sur les noyaux : ce sont des exécutables, et ils
vivent sous `/usr/share/marionnet/kernels` parce que **c'est là que Marionnet les cherche**
(`MARIONNET_KERNELS_PATH`, le même chemin que dans le canal tarball). Les déplacer vers
`/usr/lib` pour plaire à la politique ferait diverger les deux canaux.

### Le catalogue apprend un cinquième motif

`Makefile.d/release.sha256sums.sh` ne connaissait que `kernels_*`, `filesystems_*` et
`marionnet_*.tar.*` ; il connaît maintenant `*.deb`. Sans cela, un `.deb` déposé serait
**invisible** du catalogue d'une release — la règle de l'épisode 8 — et un run global aurait
laissé les quatre lignes sans jamais les écrire. Rappel écrit à cette occasion : ces fichiers
seront **aussi** décrits par le catalogue d'apt (`Packages`/`Release`, à écrire au point (5)),
ce qui n'est pas la divergence que l'épisode 8 redoutait — deux catalogues du même répertoire,
un par consommateur — mais fait tenir la règle **deux fois**.

Côté consommateur, rien à changer et c'est **vérifié** : `marionnet-install.sh --list` sur le
répertoire enrichi affiche ses dix artefacts et **ignore les quatre lignes `.deb`** sans un
mot, son classement exigeant `.tar.{gz,xz}`.

### Prouvé (2026-08-31)

- **Les quatre paquets fabriqués d'un geste**, `bash Makefile.d/release.deb.sh --force`, en
  **37 s** ; les quatre inscrits dans `SHA256SUMS` (18 artefacts) et `--check` **vert sur les
  quatre**.
- **Idempotence** : un second run sans `--force` ne fait rien en **0,12 s** — le test « déjà
  là » est posé **avant** la compilation de l'application et avant les 57 Mio dépliés d'une
  image, pas seulement avant l'appel à `dpkg-deb`.
- **Contenu mesuré** : `mtime` de l'image conservé (2017-06-09), `root:root` partout, lien
  symbolique du routeur intact, conffile déclaré, `postinst`/`prerm` valides (`sh -n`), et
  aucun des trois fichiers du tarball qui n'ont rien à faire sous `/usr`.

### Restes (pour 15b)

- **Rien n'est encore installé.** `dpkg -i` sur les quatre boîtes, l'ordre des dépendances,
  le dépôt **à plat** (`Packages`/`Release` par `dpkg-scanpackages`) et l'`apt install` qui
  va avec.
- **La dépendance de `marionnet-kernels-i386`** — `libc6:i386` est écrit, mesuré sur *cette*
  machine (l'interpréteur `/lib/ld-linux.so.2` appartient à `libc6:i386` et non à
  `libc6-i386`) ; il reste à voir ce que les quatre boîtes en font, y compris le
  `dpkg --add-architecture i386` que cela implique.
- **Le conffile déjà posé par le tarball** : la question de dpkg, à provoquer pour de vrai.
- **Debian 12** reste hors d'atteinte pour le paquet `marionnet` (glibc 2.36 < 2.38), et
  c'est désormais apt qui le dira — ce que l'épisode 12 devait écrire dans un nom de fichier.

## Épisode 15b (2026-08-31) — les quatre `.deb` s'installent, sur les quatre boîtes

Point (4) de la feuille de route, **second temps**. L'épisode 15a fabriquait les paquets et
les contrôlait **là où ils sont fabriqués** ; il ne pouvait pas jouer le geste qui en fait
une **installation**, parce que ce geste est `apt install` sur une machine qui n'est pas
celle-ci. Deux livrables : le **dépôt apt à plat** qui rend le répertoire de release lisible
par apt, et un **troisième banc** qui joue l'installation sur les quatre boîtes.

### 1. `Makefile.d/release.apt.sh` — le répertoire de release devient un dépôt apt

Cible `make release-apt` ; appelée d'elle-même par `release.deb.sh`, **une fois, après la
boucle** (l'index décrit tout le répertoire : l'écrire quatre fois ne ferait que rendre les
trois premières fausses un instant). Elle écrit trois fichiers à côté des `.deb` :
`Packages`, `Packages.gz` et `Release`. Une ligne suffit alors à atteindre le dépôt :

```
deb [trusted=yes] https://www.marionnet.org/download/marionnet-install.sh/1.0.x/ ./
```

**Dépôt à plat (`./`), pas un arbre `dists/` + `pool/`.** Une release de Marionnet est
**déjà** un répertoire par série, portant les images, les noyaux, le tarball et les quatre
paquets : la série *est* la suite, le répertoire *est* le composant, et un arbre
`dists/pool` mettrait les mêmes quatre fichiers à un second endroit sous un second nom.

**Deux catalogues cohabitent dans ce répertoire, et c'est voulu** (décidé à l'épisode 13,
réalisé ici) : `SHA256SUMS` répond à `marionnet-install.sh` (noms et empreintes des
**artefacts**), `Packages` répond à apt (champs de contrôle des **paquets** seulement).
Aucun ne se dérive de l'autre — `SHA256SUMS` ignore ce qu'est un `Depends:`, `Packages`
ignore qu'il existe une image de 5 Gio.

**Les index ne sont PAS des artefacts, donc ils ne sont pas enregistrés dans
`SHA256SUMS`.** Trois raisons, dont la première suffirait : ils sont **réécrits à chaque
publication**, donc un digest enregistré pour eux serait périmé tout seul — exactement la
panne que l'épisode 9b avait dû réparer pour les artefacts. Ensuite, apt porte déjà leur
intégrité : `Release` contient la taille et les empreintes des `Packages`, et seul `Release`
aura un jour besoin d'une signature. Enfin, un installeur qui lit `SHA256SUMS` comme une
liste de choses à télécharger ne doit pas se voir proposer un index comme s'il en était une.

**Non signé, aujourd'hui**, d'où le `[trusted=yes]` écrit noir sur blanc. `Release` est
l'endroit où une signature s'attache ; la signature est la question de l'**épisode
serveur** — c'est elle qui décide de la clef que `signed-by=` nommera — et inventer une clef
ici serait inventer la réponse.

**`dpkg-scanpackages`, pas `apt-ftparchive`** : le premier vient de `dpkg-dev`, que
`release.deb.sh` exige déjà (`dpkg-deb`, `dpkg-shlibdeps`) ; le second ajouterait `apt-utils`
à ce qu'une machine de release doit porter, pour un `Release` qui fait dix lignes. Deux
détails payés à la mesure : `--multiversion` (une release peut légitimement porter deux
révisions de l'application le temps d'un remplacement, et un index qui en cache une fait
échouer `apt install marionnet=<vieux>` sans raison lisible — cas **rencontré pour de vrai**
dès la fin de l'épisode, le commit de 15a ayant fait passer la révision de r913 à r914 : le
banc lit donc la **plus grande** version, comparée par `dpkg --compare-versions`, parce que
l'ordre des versions Debian est le sien et que `sort -V` ne sait pas ce que vaut
`0~trunk+r913`), et **aucun fichier
d'*override*** — en passer un vide (`/dev/null`) ne veut pas dire « pas d'override », mais
« un override vide », et `dpkg-scanpackages` avertit alors à chaque run que les quatre
paquets y manquent (mesuré). `Architectures:` est **dérivé** des paquets présents : oublier
`all` ferait ignorer `marionnet-fs-guignol` sans un mot.

### 2. Le banc — `Makefile.d/release.deb.sh.bench/`, 33 cas × 4 boîtes

**Résultat : 33 verts** sur Debian 13, Ubuntu 24.04 et Ubuntu 26.04 ; **7 verts** sur
Debian 12, où les cas qui installent l'application s'effacent au profit du refus qu'apt doit
énoncer (cf. (c) ci-dessous). Discriminance mesurée sur un dépôt-témoin : **SKIP 77** sans
les index (l'état d'avant cet épisode), **1 rouge** pour un `Release` périmé, **1 rouge** pour
un index enregistré dans `SHA256SUMS`, **2 rouges** si l'exclusion Docker du § 4 reste en
place.

Un **troisième** banc, et non cinq cas de plus dans celui du tarball. Le banc du tarball part
d'une boîte **portant déjà** `REQUIRED_PACKAGES_RUNTIME`, parce qu'un humain a dû les
installer d'abord (l'épisode 10 a fait en sorte qu'`install.sh` les **nomme**) ; celui-ci part
d'une boîte **nue**, parce que toute la promesse du canal `.deb` est qu'apt résout cette liste
lui-même. Fusionner les deux obligerait l'une des deux boîtes à mentir sur ce qu'elle
représente. D'où aussi l'absence de `Dockerfile` : il n'y a rien à construire, la boîte *est*
l'image de base, et ce qui est monté en lecture seule est le **vrai répertoire de release**,
index compris.

Ce qu'il établit, et qui n'était jusqu'ici qu'une affirmation : `apt install marionnet` sur
une boîte nue tire **lui-même** les treize dépendances (les douze commandes appelées par leur
nom nu sont là) ; **23 noms** dans `/usr/bin`, **12 fichiers de complétion**, les **guides de
l'épisode 14** et le `copyright` ; la conffile est **déclarée** comme telle et redirige le
préfixe compilé vers `/usr`, ce que `--paths` confirme depuis le binaire ; le `postinst`
**nomme** la règle sudoers et n'en accorde **aucune** ; le binaire **démarre** sur une boîte
qu'apt seul a garnie ; l'image guignol y arrive avec le `mtime` du tarball publié
(`2017-06-09 15:01:16`, comparé des deux côtés) et le routeur est toujours un **lien** ;
`apt remove` garde la configuration, `apt purge` la retire.

**Ce que la discriminance a appris au passage** : avec `[trusted=yes]`, **apt accepte** un
dépôt dont le `Release` ne décrit pas le `Packages` posé à côté — la vérification saute avec
la signature. Tant que le dépôt n'est pas signé, la cohérence des deux index n'est donc
gardée que par nous : c'est le cas *hôte* du banc qui l'attrape, et la raison pour laquelle
`release.apt.sh` les écrit **ensemble**, jamais l'un sans l'autre.

### 3. Les trois mesures que seul cet épisode pouvait faire

**(a) La dépendance i386, la seule du découpage qui ne se dérive pas du `Makefile`.**
`libc6:i386` avait été lu sur cette machine de développement *seulement*. Mesuré sur les
boîtes : sans `dpkg --add-architecture i386`, apt **refuse** `marionnet-kernels-i386` en
**nommant** `libc6:i386` ; avec, l'installation passe et `/lib/ld-linux.so.2` — l'interpréteur
écrit **en dur** dans le noyau 32 bits — apparaît. La décision de l'épisode 13 (un paquet
capable de faire activer une architecture étrangère ne s'impose pas à tout le monde pour de
la rétro-compatibilité) est donc chiffrée, et non plus seulement raisonnée.

**(b) La rencontre des deux canaux — ce que cet épisode a APPRIS.** Sur une machine où le
**tarball** avait déjà écrit `/etc/marionnet/marionnet.conf` (préfixe `/usr/local`), un
`apt install` **non interactif échoue** : `DEBIAN_FRONTEND=noninteractive` gouverne *debconf*,
**pas** l'invite de conffile de dpkg, qui demande, ne trouve pas de `stdin` et laisse le
paquet **non configuré** (« *end of file on stdin at conffile prompt* »). C'est Debian se
comportant exactement comme il le doit — une configuration écrite par un humain n'est jamais
écrasée en silence — et c'est une **conséquence réelle** ici, puisque les deux canaux du
chantier se rencontrent précisément chez les utilisateurs qui essaient le tarball d'abord.
Le banc mesure donc **les deux moitiés** : le refus, puis la réponse de l'administrateur
(`-o Dpkg::Options::=--force-confold`), qui termine l'installation, **conserve** le préfixe
choisi et laisse la version du paquet en `.dpkg-dist`.

**À ne pas « réparer » dans le paquet** : un `postinst` qui répondrait à cette question à la
place de l'administrateur est un paquet qui jette le préfixe qu'il avait choisi. Cela
appartient à la **doc INSTALL** (dernier épisode du chantier), qui devra écrire cette ligne
`--force-confold` et dire pourquoi elle existe.

**(c) Le refus glibc, dit par apt.** L'épisode 12 ne savait écrire cette contrainte que dans
un **nom de fichier**, et le banc du tarball devait relire ce nom pour ne pas condamner à tort
une boîte trop ancienne. Ici c'est un champ `Depends:` — le banc le lit **dans l'index** — et
sur **Debian 12** apt refuse en **nommant `libc6`** (`libc6 (>= 2.38) but 2.36-9+deb12u14 is
to be installed`). Comme au banc du tarball, la boîte trop ancienne ne fait pas sauter le
run : seuls les cas qui **installent l'application** s'effacent. Conséquence à garder
présente : *pour servir Debian 12, il faudra construire sur Debian 12* — le `.deb` rend la
contrainte **refusable**, il ne la résout pas (c'est le point 4 des prochaines étapes, la
matrice de compilation).

### 4. Un piège durable établi ici : une image Docker n'est pas une machine Debian

`debian:*-slim` **et** `ubuntu:*` embarquent une configuration dpkg qui **exclut**
`/usr/share/doc/*` (`path-exclude`, mesuré sur les deux familles ; Ubuntu y jette aussi les
pages de man et les traductions `/usr/share/locale/*/LC_MESSAGES/*.mo`). Laissée en place,
la boîte jetait les **26 guides** que l'épisode 14 venait d'installer, et le banc aurait
signalé comme défaut du paquet ce qui est un **trait de la boîte** — d'où le retrait de ce
fichier dans chaque conteneur, avant toute installation.

Le banc du tarball n'avait jamais rencontré ce piège : `tar` ne consulte la configuration de
personne. C'est exactement ce qui fait que le canal `.deb` livre **moins** que le tarball sur
une telle image, et c'est un point que le futur **canal Docker officiel** (§ 4) devra traiter
au lieu d'en hériter. Heureusement, `/usr/share/marionnet/locale` est **hors** de l'exclusion
d'Ubuntu (qui ne vise que `/usr/share/locale/`) : l'i18n survit, la documentation non.

## Épisode 16 (2026-08-31) — `marionnet-get-images` : les grosses images, choisies

Épisode **hors feuille de route**, ouvert sur une question de l'auteur : *pourquoi wheezy et
trixie ne sont-ils pas des `.deb` ?* La réponse (§ 6, rejugée à l'ép. 13) tient, mais elle
laissait un trou réel côté utilisateur — celui qui installe par apt ne recevait qu'**une
phrase** de `postinst` lui disant d'aller chercher les grosses images ailleurs.

### 1. Ce qui a été écarté, et pourquoi

La proposition initiale était un **paquet installeur** (`marionnet-fs-trixie-39212.deb` dont
le `postinst` téléchargerait). Écarté, sur trois motifs qui ne sont pas des préférences :

- **un `postinst` qui télécharge 1,09 Gio tient le verrou d'apt** pendant tout le transfert ;
  si le lien lâche, dpkg laisse le paquet en `half-configured` et l'on repart de zéro ;
- **dpkg ne posséderait aucun des 5,1 Gio** : `dpkg -L` ne listerait rien, `apt remove` ne
  libérerait rien, et un `postrm` qui effacerait des fichiers que dpkg n'a jamais
  enregistrés pourrait effacer une image posée par l'utilisateur. Le nom du paquet
  **mentirait** à apt — le contraire exact de la discipline de l'ép. 15a ;
- **les cases à cocher dans un `postinst` ne s'afficheraient pas** dans le cas le plus
  courant : debconf sous `DEBIAN_FRONTEND=noninteractive` saute la question. L'ép. 15b vient
  précisément de mesurer qu'une invite (celle de conffile) fait **échouer** un `apt install`
  non interactif ; en ajouter une seconde redoublerait une panne connue.

Ce qui était **juste** dans la proposition et a été gardé tel quel : éviter dpkg pour ces
images, et offrir une **sélection par cases à cocher** où les images déjà présentes sont
cochées et non éditables.

### 2. Ce qui a été fait : un mode, pas un script de plus

`bin/scripts/marionnet-install.sh` — **déplacé** de `useful-scripts/`, et c'est le cœur de
l'épisode — devient aussi le **chooser d'images** d'un Marionnet installé, sous les noms
`marionnet-get-images` et `mrn-get-images`, par **dispatch sur `$0`** : la forme déjà
employée par `mrn2sh` (§ 2 de `docs/move-and-rename-useful-scripts-to-bin-scripts.md`), un
fichier réel et des liens.

**Pourquoi pas un script à part** : le chooser a besoin du catalogue, de l'extraction en flux
`xz -dc -T0` et de l'empreinte vérifiée **pendant** l'extraction — c'est-à-dire de ce
fichier en entier. En réécrire une seconde implémentation est exactement ce que l'ép. 8 a
supprimé. **Et pas une bibliothèque sourcée non plus** : ce fichier est publié **seul** sur
le site et téléchargé par une machine qui n'a rien, donc il ne source rien (ép. 6 et 9c).

**Nuance apportée à la règle fondatrice** (`useful-scripts/` = le projet, `bin/scripts/` = le
binaire) : ce script est **les deux**. Il installe le projet *et* il est le compagnon qu'un
Marionnet installé appelle pour ses images. Il vit donc désormais du côté du binaire, et il
est installé — 15 noms dans `$(PREFIX)/bin/` deviennent **18**.

**Ce que le nom retire** : `--binary` est **refusé** sous `marionnet-get-images` (rc 2, en
nommant la commande qui le fait). Une machine qui fait déjà tourner Marionnet a demandé des
**images** ; un tarball déplié par-dessus un `.deb` laisserait dpkg propriétaire de fichiers
qu'il ne connaît plus.

Sous son **propre** nom, l'installeur garde `--binary` — y compris sur une machine servie par
apt. Ce qui l'empêche d'y faire des dégâts n'est pas un garde-fou de plus mais le **préfixe
par défaut** : `/usr/local`, là où le paquet occupe `/usr`. Les deux cohabitent donc, et il
faut un `--prefix /usr` **explicite** pour que l'un recouvre l'autre.

Le `postinst` du paquet `marionnet` **nomme** cette commande — *nommer, ne pas faire*, comme
pour la règle sudoers (ép. 15a) et les dépendances apt (ép. 10).

### 3. L'état d'une image, lu dans son `.conf` et non dans un digest

Une image **installée** est le fichier **extrait** ; `SHA256SUMS` porte l'empreinte du
**tarball** dont elle est sortie : les deux ne sont pas comparables. Ce qui voyage à côté de
l'image, c'est son `.conf`, qui enregistre `SUM`, `MD5SUM` et `MTIME` — et **`MTIME` est le
champ qu'UML vérifie** contre le *backing file* avant de démarrer. Comparer `mtime` et taille
est donc à la fois **O(1)** et le contrôle qui décide réellement si Marionnet ouvrira un
projet fait avec cette image.

- présente **et** intacte → ligne **cochée, sans numéro ni crochets** : il n'y a rien à
  décider, et une case qu'on ne peut pas décocher est une case qui ment sur sa nature ;
- présente mais `mtime` en désaccord → dite telle quelle, et **restée éditable** : c'est la
  ligne qu'on veut pouvoir re-télécharger ;
- absente → éditable, décochée.

**Piège mesuré** : `stat -c %Y` sur une image **routeur** lit le `mtime` du **lien**, pas de
sa cible, alors que le `.conf` du routeur enregistre le `MTIME` de l'image machine (les deux
`.conf` portent le même `MD5SUM` — c'est le même fichier). Sans `-L`, **tout routeur
fraîchement installé était signalé comme altéré**.

### 4. Une trouvaille : le `MD5SUM` du `.conf` de guignol est périmé

En écrivant la commande de vérification à la demande (`v <n>`, qui lit le fichier en entier),
mesuré sur la release 1.0.x publiée :

| image | `SUM` du `.conf` | `sum(1)` réel | `MD5SUM` du `.conf` | `md5sum` réel |
|---|---|---|---|---|
| `machine-debian-wheezy-08367` | 08367 | **08367** | 25aaf83e… | **25aaf83e…** |
| `machine-guignol-18474` | 18474 | **18474** | e7b651d1… | **afe9d7e8…** ✗ |

Le `.conf` de guignol porte donc l'empreinte MD5 d'un **état antérieur** de l'image, tandis
que `SUM` et `MTIME`, eux, sont exacts — et c'est vrai **à la source**, dans le répertoire de
release comme dans le tarball. **Rien dans Marionnet ne lit `MD5SUM`** : `bin/disk.ml:456` le
déclare parmi les variables du `.conf` et ne le consulte jamais. C'est donc une **métadonnée
périmée**, pas une image cassée.

Conséquence de conception : `v <n>` ne prononce **pas un verdict unique**. Il rend compte des
**deux** champs séparément, en disant que `SUM` est celui qui porte l'identité de l'artefact
(c'est le nombre dont l'artefact tire son nom). Un chooser qui crierait « corrompue » à chaque
guignol fraîchement installée serait un chooser qu'on ne croit pas deux fois.

*Reste à faire, hors de cet épisode* : régénérer le `MD5SUM` du `.conf` de guignol. Peu
coûteux (le `mtime` de l'**image** n'en serait pas touché, seulement celui du `.conf`), mais
cela change le tarball publié, donc son empreinte et sa ligne de `SHA256SUMS`.

### 5. Deux refus, pour que le défaut ne soit pas silencieux

- **Pas de terminal → refus** (rc 2), sous ce nom seulement. Le défaut de `--fetch-only` est
  **tout ce qui est publié**, soit ici quelque 7 Gio : `marionnet-get-images </dev/null` ne
  doit pas devenir une façon de lancer cela par surprise. Sous le nom de l'installeur, ce
  défaut est le comportement documenté de longue date et n'a **pas** été touché.
- **Pas de seconde confirmation.** Le menu montre chaque nom, chaque taille et les deux
  répertoires, et l'utilisateur a appuyé sur Entrée : reposer `Proceed? [y/N]` juste après,
  c'est poser deux fois la même question, ce qui apprend à répondre sans lire.

### 6. Preuves

| banc | avant | après |
|---|---|---|
| `Makefile.d/release.binary.sh.bench/` | 48 verts | **48 verts** (le cas des noms passe de 23 à **26**) |
| `Makefile.d/release.deb.sh.bench/` | 33 verts | **33 verts** (sur un `.deb` reconstruit) |
| `bin/scripts/marionnet-install.sh.bench/` | 63 cas | **68 cas, 68 verts** — 5 pour le second nom |

Les 5 cas neufs : `--help` se présente comme le chooser ; `--binary` **refusé** (rc 2) en
nommant ce qui installe l'application ; **sans terminal, refus** au lieu de tout prendre ;
sous le nom de l'installeur, `--fetch-only` prend **toujours** tout, sans rien demander ; et
le menu, joué avec un vrai pty, liste les images et sort proprement sur `q`.

**Piège de banc payé ici** : un conteneur lancé avec `-t` **ne peut pas** être alimenté par
un tube (« *the input device is not a TTY* », mesuré) — le pty s'alloue donc **dans** le
conteneur, par `script`. Et le déplacement a cassé un chemin relatif sortant :
`$HERE/../../Makefile.d/…` demandait désormais **trois** niveaux, si bien que le banc
**sautait** (SKIP) au lieu de tourner — ce qu'un décompte de FAIL ne montre pas.

## Épisode 17 (2026-08-31) — le canal RPM : trois paquets, et deux dépendances que personne ne porte

Épisode **hors feuille de route**, comme le 16 : la feuille de route (§ 5 bis) plaçait le RPM
en dernier, après Docker. Il est joué maintenant sur demande, et il déplace deux choses que le
§ 3.2 tenait pour acquises.

### 1. Le constat qui commande tout le reste : vde2 n'est *pas* retiré de Fedora, il n'y est jamais entré

Le § 3.2 annonçait un canal RPM pour « Fedora/openSUSE » en supposant que les dépendances
d'exécution s'y trouveraient. **Elles n'y sont pas.** Mesuré le 2026-08-31, en conteneur :

| Sonde | Résultat |
|---|---|
| `vde2` (donc `vde_switch`, `wirefilter`, `slirpvde`) | **absent** de Rocky 9 + EPEL9 + CRB + epel-next, et de **Fedora 42 comme 44** |
| `uml_mconsole` | fourni par **personne** sur Fedora 42 ni sur openSUSE Leap 15.6 |
| `glibc.i686` fournit `/lib/ld-linux.so.2` | **oui, depuis `baseos`** — le multilib est natif |
| openSUSE Leap 15.6 **et** Tumbleweed | `vde2` **présent**, dépôt OSS officiel (`2.3.2+svn587`) |

Ce n'est **pas un retrait** : le dist-git de Fedora contient **zéro** projet `rpms/vde*`
(API `src.fedoraproject.org`, `total_projects: 0`), le Bugzilla Red Hat aucune *review
request*, et la seule trace est une proposition de paquet postée sur `rhl-devel-list` en
**juin 2007**, jamais aboutie. Les RPM « Fedora » qui circulent viennent de dépôts **tiers**
(`rpm-sphere`, PLD, openmamba). Pendant ce temps Debian maintient les deux (équipe *VSquare*,
~10 patches, dernier envoi janvier 2026) sur un amont figé depuis **2011**.

La fracture n'est donc pas « RPM contre DEB » — openSUSE a `vde2` — mais **Fedora/RHEL contre
tous les autres**. Et comme `vde_switch`/`wirefilter`/`slirpvde` totalisent **19 sites
d'appel** dans `bin/` et `uml_mconsole` **4** (`simulation_level.ml`, `serial.ml`, 2 scripts),
un Marionnet installé sans eux démarre et ne fait rien.

**Ce qui a été écarté** : `alien`. Il convertit des *formats* (deb ↔ rpm), or openSUSE → Fedora
n'est pas une conversion de format ; il ne traduit pas les noms de dépendances, ne recompile
pas contre une autre glibc, n'invente pas un `vde2` absent, et **abîme** scriptlets et
attributs. Passer le `.deb` binaire de vde2 à alien livrerait des binaires liés aux sonames
Debian : ça s'installe et ça échoue à l'exécution.

**Ce qui a été fait à la place** : `release.rpm.sh` sait construire `vde2` et `uml-utilities`
**depuis le paquet source Debian** — tarball amont *plus la série de patches*, parce que ces
patches sont les quinze ans qui séparent un code de 2011 d'un compilateur de 2026. Mesuré :
les 10 patches de vde2 s'appliquent **sans un échec**.

### 2. Trois paquets Marionnet, pas quatre — et c'est mesuré, pas symétrique

Le canal Debian sépare `marionnet-kernels-i386` pour **une** raison : sa dépendance est
`libc6:i386`, une **architecture étrangère**, dont l'installation fait exécuter
`dpkg --add-architecture i386`. Sur RPM, le **même fichier** `/lib/ld-linux.so.2` appartient à
`glibc.i686`, paquet ordinaire de `baseos`. La raison du découpage n'existe pas, donc le
découpage non plus :

```
marionnet             x86_64  ~8 Mio   le binaire, les 26 noms, la complétion ×12,
                                       share/marionnet/…, les guides, la conf en %config
marionnet-kernels     x86_64  ~5 Mio   les DEUX noyaux, 64 et 32 bits
marionnet-fs-guignol  noarch  ~13 Mio  l'image guignol, machine ET routeur
```

Mieux : la dépendance multilib devient **dérivée**. `rpm -qp --requires` du paquet de noyaux
demande **les deux classes** — `libc.so.6` *et* `libc.so.6()(64bit)`, versions symboliques
comprises — parce que rpm lit les deux ELF du paquet. Ce que Debian devait écrire à la main,
ce canal le laisse déduire, ce qui **renforce** l'invariant 2 au lieu de l'affaiblir.

### 3. Un seul spec pour deux familles RPM : par fichier et par soname, jamais par nom

Les noms de paquets divergent (`gtksourceview3` contre `libgtksourceview-3_0-1`,
`iproute` contre `iproute2`, `xz-utils` → `xz`, `dnsmasq-base` → `dnsmasq`). Écrire les
dépendances **par fichier** et **par soname** rend un seul spec valable des deux côtés —
mesuré sur Fedora 42 *et* openSUSE Leap 15.6 : 9 chemins sur 9 et le soname
`libgtksourceview-3.0.so.1()(64bit)` résolvent identiquement, là où les noms échouent une fois
sur deux. La table `rpm_requires_of_debian_package` est **le seul endroit du dépôt** où un nom
Debian fait face à son équivalent RPM, et elle a exactement **deux** exceptions, toutes deux
mesurées :

- **`ip` n'a pas de chemin portable** : Fedora 42 a terminé l'usrmerge (`/usr/sbin -> bin`),
  openSUSE garde `/usr/sbin`. D'où une dépendance **booléenne** `(iproute or iproute2)`.
- **`/usr/bin/xz` a une mauvaise réponse disponible** : sur openSUSE il est aussi fourni par
  `busybox-xz`, dont le `xz` ignore le `-T` de `xz -dc -T0` (le facteur 4 de l'épisode 6).
  D'où le **nom**, `xz`, identique sur les deux familles.

`libgtksourceview-3.0-1` n'a **aucune** entrée : c'est une bibliothèque, donc rpm demande son
soname tout seul. Dériver bat traduire chaque fois que c'est possible.

### 4. rpmbuild tourne dans un conteneur, et c'est technique

Sur RPM, le **générateur automatique de dépendances est** l'équivalent de `dpkg-shlibdeps` :
c'est lui qui transforme en métadonnée refusable la contrainte de glibc que l'épisode 12 ne
savait écrire que dans un **nom de fichier**. Le faire tourner sous Ubuntu ferait de nos
métadonnées un artefact de la machine d'empaquetage plutôt que de la cible. Donc `rpmbuild`
s'exécute dans une vraie distribution RPM (`fedora:42` par défaut, `--build-image` pour une
autre), et **rien n'est installé sur la machine de release** — qui n'a d'ailleurs aucun
outillage rpm.

Corollaire tenu : le `BuildRequires:` des deux paquets tiers est **réel**, appliqué par
`dnf builddep` dans la boîte, et non recopié dans l'image du constructeur — où il aurait dérivé
du spec qui le déclare. C'est ce qui a fait apparaître `readline-devel`, sans quoi
**`uml_mconsole`** — le seul binaire que Marionnet appelle vraiment là-dedans — ne compilait pas.

### 5. Quatre pièges payés en écrivant cet épisode

1. **`make -j4` casse vde2, `make -j1` le construit.** Course dans ses Makefiles autotools de
   2011. Un build parallèle ici serait une panne *intermittente* de la chaîne de release.
2. **Une apostrophe inversée dans un heredoc non quoté mange le spec.** Le style de citation
   `` `mot' `` employé partout dans les commentaires de ce dépôt ouvre une substitution de
   commande ; le shell ne dit qu'« EOF prématurée » et le spec perd un paragraphe **en
   silence**. Guillemets doubles à l'intérieur des specs, désormais écrit là où ça compte.
3. **`local a="$1" b="$a"` ne fait pas ce qu'il semble** : tous les mots sont développés
   **avant** que les affectations prennent effet, donc `b` lit la portée appelante. `set -u`
   l'a attrapé ; deux instructions au lieu d'une.
4. **`%doc` n'est pas ce qui décide.** rpm marque **de lui-même** comme documentation tout ce
   qui vit sous `%{_docdir}` (mesuré : 26 des 31 chemins), donc `tsflags=nodocs` — que **toute**
   image conteneur RPM pose — emporte les guides quoi qu'en dise le spec. C'est le pendant exact
   du `path-exclude` de l'épisode 15b, même cause (*une image n'est pas une machine*) et même
   réponse : l'affaire du canal Docker à venir, pas une astuce d'empaquetage.

### 6. Le retrait de `RPMS/`

Les 4 specs de 2009 et leur `Makefile` sont **supprimés**. Mesuré : **aucune** cible du
`Makefile` racine ne les référence — c'était du code mort — et leur `%post` fabriquait un `br0`
dans `/etc/sysconfig/network-scripts/`, geste que l'épisode 7b de `modernisation-world-bridge` a
rendu automatique. Leur découpage (`-common`, `-fs-machines`, `-fs-routers`, `-kernels`) était
déjà réfuté au § « La décision : quatre paquets » ; le paquet routeur séparé porterait un lien
pendant.

### 7. Preuves (2026-08-31)

Banc neuf : `Makefile.d/release.rpm.sh.bench/` — **sans `Dockerfile`**, comme celui du `.deb` :
une boîte nue, tout le propos étant que `dnf` tire lui-même les dépendances.

| boîte | glibc | résultat |
|---|---|---|
| `fedora:42` | 2.41 | **37 verts, 0 rouge** |
| `rockylinux/rockylinux:9` | 2.34 | **6 verts, 0 rouge** — refus attendu, **nommant la glibc** |

Les mesures que seul ce banc pouvait faire : l'application **seule** est refusée en **nommant
les deux fichiers manquants** (et *pas* les douze autres, qui se résolvent depuis la
distribution) ; `glibc.i686` arrive **par dérivation** ; le `mtime` de l'image guignol dans le
paquet est **celui du tarball publié** (`2017-06-09 13:01` UTC des deux côtés) ; **aucune**
règle sudoers accordée ; et une configuration **modifiée** survit à la désinstallation.

### 8. Restes

- **Servir Rocky 9 et openSUSE Leap 15.6** demande de **construire sur elles** (glibc 2.34 et
  2.38 contre 2.39 ici) : la garantie glibc ne vaut que vers l'avant. C'est la conclusion de
  l'épisode 12, inchangée, et l'image de build EL9 reste à monter (`opam` n'y est dans aucun
  dépôt, `ocaml` n'y est qu'en 4.11 : switch 5.4.1 à compiler).
- **Le dépôt `createrepo`** — l'équivalent RPM de `release.apt.sh` — n'est pas fait : les cinq
  paquets s'installent par chemin, pas encore par `dnf install marionnet`.
- **La signature** des paquets et du dépôt, comme pour apt, attend l'étape « serveur ».

## Épisode 18 (2026-08-31) — le dépôt : `dnf install marionnet`

Suite immédiate du 17, et le reste qu'il nommait en premier. `Makefile.d/release.dnf.sh`
(cible `make release-dnf`, appelée d'elle-même par `release.rpm.sh` **une fois, après la
boucle**) écrit le `repodata/` d'un dépôt **à plat**, exactement comme `release.apt.sh` écrit
`Packages`/`Release` — mêmes décisions, reprises sans les rejouer.

### 1. Ce que le dépôt achète, et ce n'est pas du confort

Sans lui, l'utilisateur devait **nommer les cinq paquets** sur la ligne de commande. Or deux
d'entre eux sont ceux qu'aucune distribution RPM ne porte (épisode 17) : les nommer suppose
**savoir qu'ils existent et pourquoi**. Avec le dépôt, mesuré :

```
dnf install marionnet   →   marionnet + vde2 + uml-utilities
```

Les deux dépendances tierces sont **résolues depuis le même répertoire**. C'est la seule forme
dans laquelle « Marionnet a besoin d'un vde2 que personne n'empaquette » cesse d'être le
problème de l'utilisateur.

### 2. `Suggests:` et non `Recommends:` — un choix que la mesure a tranché

Les deux paquets de données étaient d'abord déclarés `Recommends:`. Mesuré : dnf a honoré la
dépendance faible vers `marionnet-fs-guignol` (**noarch**) et **écarté silencieusement** celle
vers `marionnet-kernels` — lequel s'installe parfaitement quand on le nomme, en tirant
`glibc.i686`. Une dépendance faible dont l'effet dépend de ce que le paquet a besoin ou non de
multilib n'est pas une promesse que ce canal peut tenir, et **la moitié qui arrive est pire que
rien** : l'utilisateur reçoit une image sans noyau, et rien ne dit pourquoi.

D'où `Suggests:`, qui **aligne les deux canaux** : `apt install marionnet` comme
`dnf install marionnet` donnent l'application seule, et le message de post-installation dit
quoi ajouter. Le même geste donne la même chose.

### 3. Trois décisions reprises telles quelles du canal apt

- **Dépôt à plat** : la série *est* le dépôt. Une arborescence mettrait les mêmes fichiers à un
  second endroit sous un second nom.
- **`repodata/` n'est PAS dans `SHA256SUMS`** : il est réécrit à chaque publication, donc un
  digest y serait périmé tout seul — la panne exacte que l'épisode 9b a dû réparer. dnf porte
  son intégrité dans `repomd.xml`, seul fichier auquel une signature s'attacherait.
- **Non signé aujourd'hui**, d'où `gpgcheck=0` dans la strophe — le pendant du `[trusted=yes]`
  de la ligne apt. La signature est la question de l'étape « serveur » : elle décide la clef.

**Trois catalogues cohabitent** désormais dans le répertoire, et aucun ne se dérive des autres :
`SHA256SUMS` (les artefacts, pour `marionnet-install.sh`), `Packages` (les champs de contrôle
des `.deb`), `repodata/` (les en-têtes des `.rpm`).

### 4. Deux points d'écriture

- **`createrepo_c` tourne en conteneur**, pour la même raison que `rpmbuild` : c'est l'outil
  d'une distribution RPM, et la machine de release n'en est pas une. Rien n'y est installé.
- **`marionnet.repo` n'est écrit que si `--base-url` le dit** (`make release-dnf BASE_URL=…`).
  L'URL d'un répertoire de release n'est pas connaissable ici — elle se décide quand le
  répertoire est servi. Écrire un fichier avec une URL devinée publierait un dépôt qui pointe
  vers rien, et le client en accuserait le serveur. Sans l'option, la strophe est **affichée**.
- **Pas de `--update`** : la seule situation où il gagnerait est celle qu'il ne faut pas rater —
  un paquet **republié sous le même nom**, que l'épisode 9b a mesurée côté apt comme un
  catalogue décrivant en silence le fichier précédent. Cinq paquets s'indexent en entier.

### 5. Preuves (2026-08-31)

Banc : **37 → 46 cas**, dont **9 neufs** dans un conteneur **neuf** (la boîte des sections
précédentes a été installée, désinstallée et sa configuration dnf éditée : « ce que donne un
`dnf install` simple » demande une machine à laquelle rien n'a été fait).

| boîte | résultat |
|---|---|
| `fedora:42` | **46 verts, 0 rouge** |
| `rockylinux/rockylinux:9` | **6 verts, 0 rouge** — le banc s'arrête au refus nommant la glibc |

Les 9 cas neufs : `repodata/repomd.xml` existe et **n'est pas** dans `SHA256SUMS` ; dnf liste
les paquets ; `dnf install marionnet` **par son nom** ; `vde2` et `uml-utilities` viennent
**avec** ; les deux paquets de données **restent dehors** mais sont **visibles** comme
suggestions ; ils s'installent sur demande, `glibc.i686` suivant le noyau 32 bits ; et, deux
révisions étant publiées, **dnf choisit la plus récente**.

**Piège de banc payé ici** : un répertoire de release contient légitimement **plusieurs
révisions** de l'application. `dnf install /rpms/*.rpm` demande alors deux versions du même
paquet et dnf refuse (« *conflicting requests* ») — ce qui faisait échouer un cas qui n'avait
rien à voir. Le banc nomme désormais les paquets un par un et choisit la plus récente
(`sort -V`).

### 6. Restes du canal RPM

Inchangés, moins celui-ci : l'**image de build à glibc ancienne** (pour servir Rocky 9 et
openSUSE Leap 15.6) et la **signature**, qui part avec l'étape « serveur » — celle-là même qui
donnera enfin une `baseurl` à `--base-url`.

## Épisode 19 (2026-08-31) — la correction : on testait les mauvaises boîtes

Épisode **né d'une question de l'utilisateur** : « pourquoi supporter Rocky 9, alors que Rocky
en est à la 10.2 ? ». La réponse a démonté quatre choses, dont trois défauts introduits aux
épisodes 17 et 18.

### 1. La mesure qui renverse le cadre

| Boîte | glibc |
|---|---|
| **Rocky Linux 10.2**, **AlmaLinux 10.2** | **2.39** = celle de la machine de compilation |
| **openSUSE Leap 16.0** | 2.40 |
| Fedora 42 | 2.41 |
| ~~Rocky 9.8~~, ~~Leap 15.6~~ | 2.34 / 2.38 — les versions **précédentes** |

**Toute distribution RPM courante accepte déjà notre build.** Le « reste » annoncé aux épisodes
17 et 18 — *une image de build à glibc ancienne* — était l'artefact d'avoir visé les versions
d'avant. Il ne disparaît pas (servir Rocky 9 le demanderait toujours) mais il cesse d'être un
préalable : ce n'est plus une impossibilité, c'est un choix de portée.

### 2. Le défaut de conception : la fusion des noyaux, à refaire

**RHEL 10 a supprimé tout le multilib 32 bits** — mesuré : *rien* ne fournit
`/lib/ld-linux.so.2` sur Rocky 10, CRB compris. Or l'épisode 17 avait **fusionné** les deux
noyaux, en s'appuyant sur une mesure faite sur Rocky **9** (où `glibc.i686` existe). Conséquence
sur la distribution entreprise courante : le paquet fusionné est refusé **en entier**, et
l'utilisateur perd aussi le noyau **64 bits**, qui lui aurait parfaitement servi.

D'où la **re-séparation** — donc les **mêmes quatre paquets** que le canal Debian, mais pour un
motif de ce monde-ci et non par symétrie : *un paquet qui ne peut pas être installé ne doit pas
en emporter un qui le peut*. Le découpage se justifie à droite par `dpkg --add-architecture`, à
gauche par l'absence pure et simple du runtime 32 bits.

Mesuré après correction, sur Rocky 10 : `dnf install marionnet` réussit,
`marionnet-kernels` (64 bits) **s'installe**, et `marionnet-kernels-i386` est refusé **seul**,
en nommant la libc 32 bits qui manque.

### 3. Deux défauts d'empaquetage, et une règle qui en sort

- **`x11-xserver-utils` → `/usr/bin/xrandr` était une devinette.** Le `Makefile` dit, dans son
  propre commentaire, que ce paquet est là pour **`xhost`**. Et `xrandr` n'existe pas du tout
  sur Rocky 10 (même avec EPEL et CRB), alors que `xhost` y est un paquet à lui seul. Corrigé :
  **lire ce que dit la source de vérité, ne pas déduire le binaire du nom du paquet**.
- **`uml-utilities` exigeait `filesystem(unmerged-sbin-symlinks)`**, que ne fournit aucune boîte
  EL. Cause trouvée dans `/usr/lib/rpm/filesystem.req` de Fedora : ce générateur se déclenche
  sur le **nom de base** d'un fichier (liste codée en dur de noms historiquement dans
  `/usr/sbin` — `uml_net` et consorts), **où qu'on l'installe**, et *ne fait rien si la boîte de
  build n'est pas usermergée*. Déplacer le fichier n'y changeait donc rien ; **changer de boîte**
  si.

D'où la règle, écrite dans l'en-tête du publieur : **on construit sur la plus ancienne boîte
qu'on sert**, pas sur la plus récente. Le générateur n'applique pas seulement `ldd`, il applique
les **conventions de la distribution où il tourne**, et celles-ci voyagent dans le paquet.
`--build-image` vaut désormais `rockylinux/rockylinux:10` par défaut. Gain accessoire : les deux
paquets tiers demandent maintenant la glibc **2.39** au lieu de la 2.41 de Fedora — exactement le
plancher de l'application elle-même.

### 4. Le défaut le plus grave était dans le banc : un PASS mensonger

Le banc classait « refus nommant la glibc » **tout** message contenant le mot. Sur Rocky 10 il a
donc affiché ce PASS alors que les vraies causes étaient `xrandr`, `gtksourceview3` et
`filesystem(unmerged-sbin-symlinks)` — **la glibc n'était pour rien**. Un banc qui valide pour
la mauvaise raison est pire qu'un banc rouge : il a été rapporté deux fois comme un succès.

Corrigé : une fonction `unmet_of` **extrait les dépendances non satisfaites**, et les cas
classent un refus par le **symbole exact** et le paquet qui le réclame. Rejoué sur Rocky 9, le
verdict est désormais `libc.so.6(GLIBC_2.38)(64bit) needed by marionnet-…`.

**Second piège de banc, payé sur openSUSE** : `zypper` imprime le problème, **annule, et sort
avec le code 0**. Un banc qui lit le statut de sortie appelle « succès » un refus. L'état se lit
maintenant dans `rpm -q`, jamais dans le code de retour.

### 5. openSUSE : la boîte qui prouve vraiment le pari des dépendances par fichier

Leap 16.0 est la 4ᵉ boîte, et elle résout avec **zypper**, pas dnf. Elle mesure ce qu'aucune
boîte Fedora/RHEL ne peut mesurer : notre `marionnet.rpm` s'y installe en résolvant
`/usr/bin/vde_switch` **depuis le vde2 de la distribution** — le nôtre n'est simplement pas tiré.
C'est précisément ce qu'achète une dépendance écrite par **fichier** plutôt que par nom de
paquet, et le cas 1 du banc l'affirme désormais dans les deux sens plutôt que d'exiger l'absence
de vde2.

Elle a aussi livré la **troisième orthographe** du même piège : l'exclusion de la documentation
s'appelle `path-exclude` chez dpkg (ép. 15b), `tsflags=nodocs` chez dnf (ép. 17) et
**`rpm.install.excludedocs`** dans `/etc/zypp/zypp.conf`. *Une image n'est pas une machine*, dans
les trois familles.

### 6. Preuves (2026-08-31)

Le banc prend `--distro all` et joue les **quatre distributions courantes** :

| boîte | résultat |
|---|---|
| `rockylinux/rockylinux:10` | **47 verts, 0 rouge** |
| `almalinux:10` | **45 verts, 0 rouge** |
| `fedora:42` | **46 verts, 0 rouge** |
| `opensuse/leap:16.0` | **46 verts, 0 rouge** |
| `rockylinux/rockylinux:9` (hors du défaut) | **6 verts** — refus classé par le symbole exact |

Soit **184 cas verts** et aucun rouge. Cas neuf : le noyau i386 refusé **seul** sur une boîte
sans multilib, la vérification portant sur le fait que **le noyau 64 bits est indemne** — ce que
le paquet fusionné de l'épisode 17 ne pouvait pas tenir.

### 7. Ce qui reste, et ce qui n'en est plus

- **N'est plus un reste** : la portée. Les quatre distributions RPM courantes sont servies.
- **Reste un choix de portée** : Rocky 9 et Leap 15.6 (glibc 2.34 et 2.38) demanderaient une
  image de build à glibc plus ancienne — possible en conteneur, au prix d'un switch OCaml 5.4.1
  compilé depuis les sources (`opam` n'est dans aucun dépôt EL9).
- **Reste bloqué par l'extérieur** : la signature et la `baseurl` réelle, avec l'étape serveur.
- **Reste à documenter** : EPEL est requis sur les boîtes EL (c'est de là que vient
  `gtksourceview3`) — une ligne pour la doc INSTALL.

## Épisode 20 (2026-08-31) — la boîte de compilation : le plancher devient un choix

L'épisode 12 avait mesuré que le binaire publié ne démarre pas sous glibc 2.39, l'épisode 13
que le `.deb` n'y change rien (il rend la contrainte *refusable*, `libc6 (>= 2.39)`, il ne la
résout pas), et l'épisode 19 avait énoncé la règle : **on construit sur la plus ancienne boîte
qu'on sert**. Cette règle n'avait été appliquée qu'aux **deux paquets tiers RPM**. L'application
elle-même était toujours compilée sur la machine de l'auteur — donc **les six canaux héritaient
d'un plancher qui était un accident de cette machine**.

### « Matrice de compilation » ⇒ un plancher, pas une matrice

La compatibilité glibc est **unidirectionnelle** : ce qu'un binaire lié dynamiquement exige de
la machine où il atterrit, c'est une glibc **au moins aussi récente** que celle contre laquelle
il a été lié. Publier N artefacts indexés par glibc reviendrait donc à en publier **N−1 dont
personne n'a l'usage** : celui du plancher sert toutes les boîtes au-dessus. Il n'y a pas de
matrice — il y a un **plancher**, et c'est un **bouton** (`--build-image`).

Conséquences, toutes vérifiées plutôt que supposées :

- **`marionnet-install.sh` n'est pas touché.** Sa règle de choix (arch de la machine, glibc pas
  plus récente que la sienne, puis le plus grand `rev`) vaut telle quelle, et vaudrait encore si
  l'on publiait un jour deux planchers.
- **Le banc binaire n'est pas touché non plus**, et c'est la conception de l'épisode 12 qui
  tient : il compare la glibc lue **dans le nom du tarball** à celle mesurée **dans la boîte**
  (`glibc_le`, `release.binary.sh.bench/run.sh:159-181`), jamais le nom de la distribution. Les
  4 cas qui démarrent le binaire se sont donc rallumés d'eux-mêmes sur Debian 12, et le cas
  « le refus doit nommer la glibc » s'est effacé de lui-même, sans une ligne de banc modifiée.
- **Plancher retenu : `debian:12` (glibc 2.36)**, qui couvre les 4 boîtes Debian/Ubuntu **et**
  les 4 boîtes RPM courantes (Rocky/Alma 10 = 2.39, Leap 16 = 2.40, Fedora 42 = 2.41). Servir
  Rocky 9 (2.34) ou Leap 15.6 (2.38) reste le **choix de portée** de l'épisode 19 — devenu
  `--build-image debian:11`, au prix d'un second switch à compiler.

### Le livrable

`Makefile.d/release.build-box.sh` (cible `make release-build-box`). Il ne sait ni ce qu'est une
installation, ni comment se nomme un artefact, ni comment on catalogue une release : **il
choisit seulement où tourne le compilateur**. Dans la boîte, ce sont `make rebuild-for-final`
et `Makefile.d/release.binary.sh` **inchangés** qui font le travail.

Rien n'y est décrit deux fois : les paquets apt de build, le compilateur et les paquets opam
sont lus **à travers `make`** (`print-required-packages-build`, `print-opam-switch`,
`print-opam-packages` — le motif de `print-required-packages-runtime` de l'épisode 10), jamais
recopiés dans le script. `OPAM_PACKAGES_DEV` n'est délibérément **pas** publié : des outils
d'édition et de documentation n'ont rien à faire dans une boîte dont le seul métier est de
produire un artefact. `glade` reste dans la liste bien que seul un développeur en ait besoin —
l'en filtrer ici recréerait exactement la seconde source de vérité que l'épisode 1 a supprimée.

### Le défaut que le premier run a publié — et il ne faut pas le défaire

**Ce qui est compilé est ce qui est committé** : la source remise à la boîte est un `git clone`
de la copie de travail à HEAD, et non la copie de travail (`_build/`, le bac à sable opam local
et le symlink `CONFIGME.choice` d'un arbre de développeur n'ont rien à faire dans un artefact
publié). Le clone **garde son `.git`**, parce que `bin/meta.ml.maker.sh:57` en dérive la
révision — un `git archive` l'aurait laissée vide en silence.

**Garder le `.git` ne suffit pas, et le premier run l'a prouvé en publiant
`marionnet_trunk-r0_amd64_glibc2.36.tar.xz`** — `r0`, là où la copie de travail est à r919.
Le clone appartient à l'appelant, le conteneur tourne en root, et git depuis 2.35.2 **refuse**
un dépôt de « propriété douteuse » (*dubious ownership*, reproduit). Or les **deux** lecteurs
de la révision traitent un git en échec comme « pas de VCS ici » :
`bin/meta.ml.maker.sh:57-68` émet un avertissement et laisse la révision **vide**,
`project_revision` de `release.binary.sh:141` retourne **0**. **Rien n'échoue** ; une release
perd simplement le numéro qui l'ordonne — et comme `marionnet-install.sh` choisit *le plus
grand `rev`*, un artefact `r0` n'aurait jamais été servi tout en occupant le catalogue.

D'où **deux** choses dans le script, et la seconde compte plus que la première :
`safe.directory`, pour que git réponde ; et surtout la **comparaison** de la révision lue dans
la boîte avec celle calculée ici — une boîte qui lit autre chose **arrête le run** (rc 3) au
lieu de publier sous un nom qui ment.

Second défaut du même genre, dans la mesure de preuve elle-même : elle cherchait
`marionnet.native` alors que **dune produit `marionnet.exe`** (`marionnet.native` est le nom
d'*installation*), et se taisait quand elle ne trouvait rien. Elle cherche les deux noms et
**échoue** (rc 4) si elle ne trouve ni l'un ni l'autre. Une mesure qui peut ne pas avoir lieu
sans que personne ne le sache n'est pas une mesure.

L'artefact `r0` a été retiré, et `release.sha256sums.sh` **a retiré sa ligne de lui-même**
(« dropping the line of a file which is no longer there ») : l'invariant de l'épisode 8 a
fonctionné sans qu'on y touche.

### Prouvé (2026-08-31)

- `make release-build-box` : boîte `mrn-build-debian-12` bâtie une fois (8 paquets apt, switch
  OCaml **5.4.1 compilé depuis les sources**, 12 paquets opam dont `lablgtk3` et `camlp4.5.4`),
  puis `marionnet_trunk-r919_amd64_glibc2.36.tar.xz` (7,2 Mio) publié et inscrit au
  `SHA256SUMS` (30 artefacts, 1 calculé).
- **Le risque nommé au plan ne s'est pas matérialisé** : l'`opam` 2.1 de bookworm crée le switch
  5.4.1 et installe les 12 paquets sans repli vers un binaire opam téléchargé.
- **La mesure du plancher, indépendante du nom du fichier** : le symbole glibc versionné le plus
  haut que le binaire référence est **`GLIBC_2.35`** — donc plus bas encore que la glibc de la
  boîte. Le nom (`glibc2.36`) reste **conservateur**, ce qui est le bon sens de la garantie :
  il annonce la boîte de construction, pas le minimum théorique.
- **Banc binaire `--distro all` : 48 + 48 + 48 + 48 = 192 verts, 0 rouge, et surtout 0 SKIP.**
  Sur `debian:bookworm-slim`, où l'artefact précédent ne pouvait que se faire refuser, les
  4 cas qui démarrent le binaire tournent maintenant — `--paths` lit la configuration installée,
  le piège `binaries` de l'épisode 9a est vérifié, et `9a -> 10 en un geste` passe.

### Restes

- **20b — le `.deb` fabriqué dans la même boîte** *(fait, section suivante)*.
- **20c — le `.rpm` de même**, dont la boîte de build est déjà un conteneur (épisode 19) mais
  dont le **staging** vient encore du binaire compilé ici.
- Servir Rocky 9 / Leap 15.6 reste un choix de portée : `--build-image debian:11`.

## Épisode 20b (2026-08-31) — le `.deb` sort de la même boîte que le binaire

### Le défaut était plus large que celui qu'on avait nommé

Le reste de l'épisode 20 annonçait une seule chose à corriger : `dpkg-shlibdeps` tournant sur la
machine de l'auteur écrivait `libc6 (>= 2.38)` pour un binaire qui n'exige que 2.35. Mesuré sur
le paquet réellement publié (`marionnet_0~trunk+r915_amd64.deb`), le `Depends:` disait :

```
libc6 (>= 2.38), …, libglib2.0-0t64 (>= 2.36.0), libgtk-3-0t64 (>= 3.11.5), …
```

**Deux défauts, et le second n'avait pas été vu.** `libgtk-3-0t64` et `libglib2.0-0t64` sont les
noms issus de la transition `time_t` 64 bits ; ils **n'existent pas du tout sur Debian 12**. Le
paquet ne demandait donc pas seulement une glibc trop récente : il nommait des paquets que la
boîte ne pouvait pas trouver. `dpkg-shlibdeps` avait écrit les **noms de paquets de la machine
où il tournait** — la règle de l'épisode 19, appliquée cette fois aux noms et non aux versions.

**Et l'asymétrie est la même que celle de la glibc, donc la réponse aussi.** Mesuré sur
`debian:trixie-slim` : `libgtk-3-0t64` déclare `Provides: libgtk-3-0 (= 3.24.49-3)`, et
`libglib2.0-0t64` fait de même. Une dépendance versionnée sur l'**ancien** nom est donc
satisfaite **au-dessus** du plancher ; l'inverse est faux. *On construit sur la plus ancienne
boîte qu'on sert* — la règle de l'épisode 19, la même que pour la glibc.

### Le livrable : un drapeau, pas un second script

`Makefile.d/release.build-box.sh --with-deb` (cible `make release-build-box WITH_DEB=1`) lance
`release.deb.sh` **dans le même conteneur**, juste après le tarball, contre le staging qui vient
d'être compilé.

**Pourquoi pas un `--build-image` sur `release.deb.sh`** : le `.deb` de l'application est
assemblé du staging que `release.binary.sh` produit **en compilant** ; empaqueter dans la boîte
implique donc compiler dans la boîte. Un second point d'entrée aurait dû recloner HEAD, faire
traverser la révision et reposer la garde `safe.directory` que l'épisode 20 a payées. **Il y a un
seul endroit où tourne le compilateur.**

Deux détails qui ont demandé une décision :

- **Les outils d'empaquetage sont une couche à eux seuls, et la dernière** (`dpkg-dev`,
  `fakeroot`, `lintian`). Les mettre avant le switch aurait fait **recompiler OCaml depuis les
  sources** à toute boîte déjà bâtie pour gagner trois paquets apt. En dernier, le `docker build`
  rejoue les deux couches d'au-dessus depuis son cache. `lintian` en fait partie **exprès** : il
  juge un paquet selon la politique de la distribution **où il tourne**, donc la boîte où les
  paquets sont désormais faits est la boîte où il a quelque chose à dire.
- **Une boîte d'avant l'épisode compile parfaitement et n'empaquette pas du tout.** Plutôt que
  d'échouer à mi-chemin — après le switch, le clone et la compilation — l'absence est trouvée
  **avant** (`box_can_package`, un `docker run` de deux `command -v`) et répondue par un rebuild
  que le cache rend bon marché.

### Le défaut du banc : sa propre leçon, ignorée deux lignes plus bas

Le premier rejeu a rendu un **FAIL** là où le paquet venait de s'installer. `run.sh` lit la
version applicative par `indexed_version`, dont le commentaire dit déjà *« la plus GRANDE, pas la
première listée : un répertoire de release peut légitimement porter deux révisions »* — mais les
deux lignes qui suivent lisaient `Architecture:` et `Depends:` avec un `awk … exit` sur la
**première** strophe `Package: marionnet`. Avec r913 (bâti ici, 2.38) à côté de r920 (bâti dans la
boîte, 2.35), le banc **annonçait r920 et le jugeait sur la contrainte de r913** : il continuait
d'attendre un refus d'une boîte qui venait d'installer le paquet.

Corrigé par `indexed_field <paquet> <version> <champ>`, qui lit la strophe **candidate**. C'est
le pendant exact du PASS mensonger de l'épisode 19 : là un refus mal classé passait au vert, ici
un succès était classé rouge — dans les deux cas le banc jugeait par autre chose que ce qu'il
mesurait.

### Prouvé (2026-08-31)

- **`release.deb.sh.bench/run.sh --distro debian:bookworm-slim` : 7 → 33 verts**, la preuve que
  le reste de l'épisode 20 demandait. Le refus glibc ne s'y joue plus — le cas s'efface de
  lui-même, comme au banc binaire de l'épisode 20 — et tous les cas qui **installent** le paquet
  tournent : dépendances résolues par apt sur une boîte nue, 26 noms dans `/usr/bin`, les 12
  fichiers de complétion, les guides, le conffile et ses trois cas, le `mtime` `2017-06-09
  15:01:16` de l'image guignol, le lien symbolique du routeur, `libc6:i386` nommé puis satisfait.
- **`Depends:` des paquets sortis de la boîte** : `libc6 (>= 2.35)` (exactement le symbole
  `GLIBC_2.35` que l'épisode 20 avait mesuré), `libglib2.0-0`, `libgtk-3-0` — les noms
  pré-transition. Noyau 64 bits : `libc6 (>= 2.34)` ; noyau i386 : `libc6:i386`.
- **`--distro all` : 33 + 33 + 33 + 33 = 132 verts, 0 rouge, 0 SKIP** (Debian 12 et 13,
  Ubuntu 24.04 et 26.04). C'est là que les `Provides` des paquets `t64` sont **éprouvés** et pas
  seulement lus : sur trixie et sur les deux Ubuntu, apt satisfait `libgtk-3-0 (>= 3.11.5)` par
  `libgtk-3-0t64` et installe. Debian 12, qui ne savait jusqu'ici que refuser, joue les 33 cas —
  le même acquis que l'épisode 20 pour le tarball, cette fois pour le paquet.

### Restes

- **20c — le `.rpm` de même.** `release.rpm.sh` fait déjà tourner `rpmbuild` dans un conteneur de
  la distribution cible (épisode 19), mais son **staging** vient encore du binaire compilé ici.
  *(Fait : § Épisode 20c ci-dessous.)*

## Épisode 20c (2026-08-31) — le canal RPM ne compile plus rien

### Le défaut, et pourquoi il survivait à l'épisode 19

`release.rpm.sh` faisait tourner `rpmbuild` dans un conteneur de la distribution cible depuis
l'épisode 19 — ce qui donnait les **métadonnées** de cette distribution — mais il obtenait son
staging en appelant `release.binary.sh --staging-dir … --no-tarball` **sur la machine de
l'auteur** (l. 576). Changer la boîte de `rpmbuild` corrigeait ce que le paquet *dit* ; cela ne
pouvait pas corriger ce qu'il *contient*, puisque les octets n'y étaient pas faits. C'était le
dernier endroit où le plancher d'un canal restait un accident de la machine de l'empaqueteur.

Son symétrique côté identité était du même ordre : `read_identity` lisait
`release.binary.sh --print-name`, donc l'arch et la **glibc de l'hôte**. Mesuré ce jour : l'hôte
nommait `marionnet_trunk-r921_amd64_glibc2.39` là où le répertoire de release publiait
`marionnet_trunk-r920_amd64_glibc2.36`.

### La forme retenue : déplier le tarball publié, plutôt qu'un drapeau de plus

L'épisode 20b a pu enchaîner dans la boîte parce que, du côté Debian, **une seule** boîte fait
les deux gestes (compiler, empaqueter). Ici elles sont nécessairement **deux** — le compilateur
dans `debian:12`, `rpmbuild` dans `rockylinux:10` — et il n'y a pas de docker-dans-docker. La
réponse n'est donc pas un `--with-rpm` qui ferait voyager un staging entre deux conteneurs,
mais la règle que ce script applique **déjà** à ses paquets de données : *un paquet décrit ce
que le répertoire de release contient*. L'application est désormais **dépliée du
`marionnet_*.tar.xz` publié**, sans `-m`, exactement comme les noyaux et l'image guignol.

Trois conséquences, et la première est le propos :

1. **Il n'y a plus rien à compiler ici**, donc empaqueter un binaire compilé sur la machine de
   l'empaqueteur n'est **plus exprimable**. Le `.rpm` et le `.tar.xz` portent le même binaire
   **à l'octet** (mesuré : `b4c6ff17…` des deux côtés).
2. **L'identité se lit dans le nom de l'artefact** — version, révision, architecture — et non
   plus dans celui que l'hôte se donnerait. Même règle que `kernel_version_of` et
   `guignol_version_of`, et même règle que `marionnet-install.sh` pour choisir.
3. **Le prix, dit franchement** : `make release-rpm` **exige** désormais un tarball publié et le
   dit (`run make release-build-box first`), là où il en fabriquait un en silence.

Un répertoire de release contient légitimement plusieurs révisions (piège de banc de
l'épisode 18) : la plus grande `r<rev>` gagne, et **deux architectures à cette révision font
refuser** plutôt que deviner — `--app-artefact` nomme alors celui qu'on veut, comme `--kernel`.

### Ce que le banc a trouvé, et que 192 + 132 verts n'avaient pas vu

Le premier rejeu a rendu un **FAIL** disant *« the binary does not run »* sur un binaire qui
venait de dire son numéro de version. Le cas lisait `2>&1 | head -1` : **toute** ligne écrite
sur stderr avant la réponse faisait classer un succès en échec. C'est le troisième défaut de
cette famille (épisode 19 : un refus mal classé passait au vert ; épisode 20b : un succès
classé rouge par une strophe lue au mauvais endroit) — un banc qui juge par autre chose que ce
qu'il mesure. Corrigé en **séparant les deux questions** : *tourne-t-il* se lit dans toute la
sortie, *démarre-t-il proprement* est un cas à lui.

Et ce cas est **rouge**, sur ce qu'il a mis au jour :

> **Le binaire compilé dans la boîte écrit un avertissement que celui compilé ici n'écrit pas.**
> `GLib-GObject-CRITICAL **: invalid cast from 'GtkSourceStyleSchemeManager' to
> 'GInitiallyUnowned'`, au démarrage, **sur toutes les boîtes** (fedora:42, debian:12,
> debian:trixie-slim). Les variables sont isolées : **r918** (compilé ici) est muet, **r919**
> (compilé dans la boîte) avertit, et le commit qui les sépare (`213bee5`, épisode 20) ne
> touche **aucun `.ml`**. Même `lablgtk3` (3.1.5), même `lablgtk3-sourceview3` (3.1.5), même
> `ocaml` (5.4.1), même `libgtksourceview-3.0` (3.24.11) des deux côtés. **La boîte de build ne
> déplace donc pas seulement le plancher glibc : elle change ce que le binaire dit.** Cause non
> établie ; l'application démarre et fonctionne. À traiter comme un épisode à part.

Ni le banc binaire (192 verts) ni le banc `.deb` (132 verts) ne pouvaient le voir : aucun ne
regarde stderr au démarrage.

### Prouvé (2026-08-31)

- **Le contrat, mesuré dans la boîte cible** : binaire du `.rpm` = binaire du tarball r920,
  `sha256 b4c6ff17…` des deux côtés ; symbole glibc maximal référencé `GLIBC_2.35` ;
  `root:root`, `mtime` conservé.
- **Discriminance sur le paquet d'avant** : `marionnet-0~trunk+r918` exigeait `GLIBC_2.38`,
  `marionnet-0~trunk+r920` exige `GLIBC_2.35` — c'est-à-dire la différence entre un paquet
  refusé sous Rocky 9 / Leap 15.6 et un paquet qui y passerait.
- **Coût** : le paquet applicatif se fait en **11 s** (dépliage + `rpmbuild`) au lieu d'une
  compilation complète.
- **Chemins d'erreur** : répertoire sans tarball applicatif → refus nommant
  `make release-build-box` (rc 2) ; `--app-artefact` inconnu → refus (rc 2) ;
  `--app-artefact marionnet_trunk-r915_…` → `marionnet-0~trunk+r915-1.x86_64.rpm`.
- **Banc RPM** : 46 → **48 cas**. `fedora:42` = 46 verts + 1 rouge ; `rockylinux:10` = 48 verts
  + 1 rouge — le rouge étant, des deux côtés, l'avertissement GLib ci-dessus. Cas neuf
  *« the installed binary is the published tarball's, to the byte »* : vert, et **sauté**
  lorsqu'aucun tarball ne correspond à la révision du paquet (un paquet peut légitimement
  précéder l'épisode 20c).

### Restes

- **Le `GLib-GObject-CRITICAL` de la boîte de build** — mesuré, isolé, cause inconnue.
  Il concerne **tous** les canaux (le tarball, le `.deb` et le `.rpm` portent le même binaire),
  donc c'est un épisode à part et non un reste de 20c.
- **La discriminance du cas d'identité binaire ne se joue pas sur l'existant** : aucune
  révision ne possède à la fois un `.rpm` d'avant 20c et un tarball publié, si bien que le cas
  neuf *saute* sur les paquets antérieurs au lieu de rougir. Le rougir demanderait de publier un
  tarball à la révision courante, donc une compilation — mesure reportée au prochain
  `make release-build-box`.

---

## Épisode 21 (2026-08-31) — la boîte ne changeait pas le binaire, elle enlevait un bâillon

Gradué par l'épisode 20c (point « 4 quater » des prochaines étapes), et **seul épisode encore
jouable** : les étapes (5) et (6) de la feuille de route attendent le retour de
`www.marionnet.org`.

### Le constat de départ, et ce qu'il faisait croire

Le binaire compilé dans la boîte `debian:12` écrivait au démarrage :

```
(process:…): GLib-GObject-CRITICAL **: invalid cast from 'GtkSourceStyleSchemeManager' to 'GInitiallyUnowned'
```

là où celui compilé sur la machine de l'auteur ne disait rien — mêmes versions des deux côtés,
révisions isolées (r918 muet / r919 bavard) et **aucun `.ml`** entre les deux. La formule retenue
alors était *« la boîte ne déplace pas que le plancher glibc : elle change ce que le binaire
dit »*. Elle était exacte comme description et **trompeuse comme diagnostic** : elle laissait
supposer un défaut *de la boîte*.

### La chaîne d'appel, lue et non devinée

Reproduit **hors conteneur**, sur les deux tarballs publiés (`r915` compilé ici, `r920` compilé
dans la boîte) et sur cette machine : `r915 --version` → rien sur stderr ; `r920 --version` →
l'avertissement. Le symptôme est donc dans le **binaire**, pas dans l'environnement d'exécution.

`gdb` avec `G_DEBUG=fatal-criticals` donne l'origine exacte, en une pile :

```
#3 ml_gtk_source_style_scheme_manager_new () at ml_gtksourceview3.c:470
#5 camlGSourceView3.source_style_scheme_manager () at src-sourceview3/gSourceView3.ml:103
#6 camlGtksv_utils.entry () at lib/gtksv_utils.ml:106
#7 caml_program ()
```

C'est du **code d'initialisation de module** : `Gtksv_utils` (de `lablgtk3-extras`) construit un
`GtkSourceStyleSchemeManager` au chargement, et le stub le fait passer par `Val_GObject_sink`,
c'est-à-dire `g_object_ref_sink` — or un `GtkSourceStyleSchemeManager` **n'est pas** un
`GInitiallyUnowned`. Le cast est faux. Marionnet n'appelle rien de tout cela.

### Pourquoi une seule des deux compilations le disait

Le même point de code, désassemblé des deux côtés :

| | `r915` (compilé ici) | `r920` (compilé dans la boîte) |
|---|---|---|
| `g_initially_unowned_get_type` | absent | appelé |
| `g_type_check_instance_cast` | absent | appelé |
| `Val_GObject_sink` | appelé | appelé |

La vérification de cast a été **compilée out** ici, et conservée là-bas. La raison est dans les
en-têtes de glib, et nulle part ailleurs :

- glib **2.80** (hôte, Ubuntu 24.04) : `#if defined(G_DISABLE_CAST_CHECKS) || defined(__OPTIMIZE__)`
  → tout build optimisé perd la vérification ;
- glib **2.74** (`debian:12`, la boîte) : `#ifndef G_DISABLE_CAST_CHECKS` → elle reste.

**Donc le défaut existait dans les deux binaires, et depuis toujours ; seule la boîte le dit.**
C'est le renversement de l'épisode : la boîte n'a pas introduit un défaut, elle a retiré un
bâillon — même famille que les PASS mensongers des épisodes 19 et 20b, un cran plus bas.

### Le correctif : ne plus lier une bibliothèque dont on ne nomme aucun module

`bin/dune` listait `lablgtk3-extras`. Aucun de ses modules — `Gdir`, `Gmylist`, `Gmytree`,
`Gstuff`, `Gtksv_utils`, `Okey`, `Configwin` — n'est nommé **nulle part** dans ce dépôt (0
occurrence, `bin/` et `lib/`). Il n'était là que pour atteindre `GSourceView3`, qui vient
transitivement avec, et dont `bin/gui/gui_source_editing.ml` est le seul client.

`bin/dune` nomme désormais `lablgtk3-sourceview3` **directement** — paquet déjà présent dans
`OPAM_PACKAGES`, donc rien à installer de plus, et `lablgtk3-extras` en est retiré (ses propres
dépendances `ocf` et `xmlm` partent avec lui). Le module fautif n'est plus lié, son code
d'initialisation ne s'exécute plus, l'appel disparaît.

**Ce que le correctif ne fait pas** : il ne répare pas le stub de `lablgtk3-sourceview3`, qui
reste faux en amont. Il rend seulement le dépôt indépendant de lui. Si un jour un module de ce
dépôt appelle `source_style_scheme_manager`, l'avertissement reviendra — et il aura raison.

### Prouvé (2026-08-31)

- **Le symptôme, reproduit sur l'hôte** avant tout correctif : `r920` bavard, `r915` muet,
  sans conteneur. C'est ce qui autorise à travailler ici plutôt que dans la boîte.
- **La cause, lue** : pile `gdb` complète (le site d'appel est du code d'initialisation de module,
  pas du code de Marionnet) ; désassemblage comparé des deux stubs ; les **deux** macros
  `_G_TYPE_CIC` lues, celle de l'hôte et celle de `debian:12` (dans un conteneur `debian:12`,
  `libglib2.0-dev 2.74.6-2+deb12u9`).
- **Le correctif, mesuré** : `dune build` rc 0, `dune build @check` rc 0 (tous les modules, pas
  seulement la clôture atteignable) ; `nm` sur le binaire → **0** symbole `camlGtksv_utils`
  (contre 309 avant) et **862** `camlGSourceView3` **inchangés** ; breakpoint `gdb` sur
  `ml_gtk_source_style_scheme_manager_new` **jamais atteint** (il l'était sur `r915` **et** sur
  `r920`) — l'unique source possible du message a disparu, quelle que soit la boîte.
- **Non-régression fonctionnelle** : `driven-sessions/quit-is-observable.sh` **7/7**, donc une
  vraie GUI démarre, répond par le canal et se termine sans `lablgtk3-extras`.
- **Banc RPM** : le cas *« the binary starts cleanly »*, rouge exprès depuis 20c, redevient
  vert — son commentaire porte maintenant la cause au lieu de la constater.

### Restes

- **La preuve de bout en bout attend le commit** : `release.build-box.sh` clone `HEAD`
  (*what is compiled is what is committed*, invariant de l'épisode 20), donc le rejeu
  `make release-build-box` + banc RPM se joue **après** que cet épisode soit committé. La mesure
  locale ci-dessus est décisive sur la cause ; celle-là est le contrôle de la chaîne.
- Ce rejeu réveillera aussi le cas d'identité binaire de 20c, qui *saute* faute d'une
  révision portant à la fois un `.rpm` et un tarball publié.

## Épisode 22 (2026-08-31) — le contrôle de chaîne : la boîte confirme l'épisode 21

Épisode de **mesure**, sans code : le point « 4 quinquies » des prochaines étapes, dont l'ordre
était **imposé** par un invariant de l'épisode 20 — `release.build-box.sh` clone **`HEAD`**
(*what is compiled is what is committed*), donc la preuve de bout en bout de l'épisode 21 ne
pouvait se jouer qu'**après** son commit (`87365bc`). La mesure locale de 21 était décisive sur
la *cause* ; celle-ci est le contrôle de la *chaîne*, et elle est la seule que cette machine ne
peut pas faire seule : ici glib ≥ 2.80 **compile la vérification de cast out** sous
`__OPTIMIZE__`, donc un binaire muet n'y prouve rien.

### Ce qui a été joué

1. `make release-build-box` — clone de `HEAD` (r923, révision **concordante** avec celle
   calculée côté hôte : la garde de l'épisode 20 n'a pas eu à s'en mêler), compilation dans
   `debian:12`, publication de `marionnet_trunk-r923_amd64_glibc2.36.tar.xz` (7,1 Mio,
   `SHA256SUMS` à 34 artefacts).
2. `make release-rpm` — **aucune compilation** : le tarball r923 est déplié, d'où
   `marionnet-0~trunk+r923-1.x86_64.rpm` (8,1 Mio, 35 artefacts, `repodata/` réécrit à
   10 paquets).
3. `Makefile.d/release.rpm.sh.bench/run.sh` sur les **deux** boîtes du canal.

### Prouvé (2026-08-31)

- **`fedora:42` : 48 passed, 0 failed, 0 skipped.** **`rockylinux/rockylinux:10` : 49 passed,
  0 failed, 0 skipped.** L'écart d'un cas est celui, connu, de l'épisode 19 : EL 10 n'ayant plus
  de multilib 32 bits, le refus de `marionnet-kernels-i386` y est classé **par son symbole exact**
  (`libc.so.6(GLIBC_2.0)`) et s'accompagne d'un second cas — *le noyau 64 bits est indemne*, ce
  que le paquet fusionné de l'épisode 17 ne savait pas faire.
- **Le cas *« the binary starts cleanly (nothing on stderr) »* est VERT sur les deux boîtes.**
  Rouge exprès depuis 20c, il l'est resté jusqu'à ce qu'un binaire compilé dans la boîte porte
  l'épisode 21 : c'est la preuve que le `GLib-GObject-CRITICAL` a disparu **là où glib le dit
  encore**, et non seulement là où le compilateur le taisait.
- **Le cas d'identité binaire de 20c passe de SKIP à VERT** : r923 est la première révision à
  porter **et** un `.rpm` **et** un tarball publié, et le binaire installé par rpm est celui du
  tarball **à l'octet**. Le contrat de 20c — *ce canal ne compile rien* — cesse d'être une
  intention pour devenir une mesure.
- Plancher inchangé : symbole glibc versionné le plus haut référencé = **`GLIBC_2.35`**, nom de
  l'artefact conservateur en `glibc2.36` (il annonce la boîte de build, épisode 20).

### Ce que l'épisode ne change pas

Aucun fichier de code, aucun banc modifié : les commentaires des deux cas avaient été écrits par
l'épisode 21 pour l'état d'*après* (« green from episode 21 on »), et ils disent juste. La seule
correction est une phrase de la section « Restes » de l'épisode 21, qui annonçait le cas
d'identité **rouge** au rejeu là où il ne pouvait que virer au vert.

## Épisode 23 (2026-08-31) — le `MD5SUM` régénéré, et la dérive de `mtime` qu'il a révélée

Dernier point local jouable (les étapes (5) et (6) attendent le retour du serveur) : le
`MD5SUM` du `.conf` de `machine-guignol-18474`, mesuré **périmé à la source** par l'épisode 16
(`SUM` et `MTIME` exacts, `md5sum` non). Étape annoncée « peu coûteuse ». Elle l'était ; mais
pour la jouer il fallait **republier**, et c'est la republication qui a découvert le vrai
défaut.

### 1. Ce que la republication allait publier

Le mode « image déjà publiée » de `filesystem.prepare-snapshot-to-publish.sh` ne recalcule
rien : il archive l'image **telle qu'elle est sur le disque**, `mtime` compris. Or, mesuré dans
le répertoire de release `1.0.x` :

| image | `mtime` sur le disque | `MTIME` de son `.conf` |
|---|---|---|
| `machine-guignol-18474` | 1788092033 (2026-08-30) | 1497013276 (2017-06-09) |
| `machine-debian-wheezy-08367` | 1788092026 (2026-08-30) | 1404061349 (2014-06-29) |
| `machine-debian-trixie-39212` | 1788091856 (2026-08-30) | 1787511417 (2026-08-23) |

Les **trois** images nues du répertoire avaient perdu leur `mtime` le 2026-08-30 entre 14h10 et
14h13 — une copie sans `-p` fait exactement cela — tandis que leurs tarballs, construits dix
minutes plus tôt, portaient encore le bon. Un `--force` joué ce jour-là aurait donc publié
des images au `mtime` neuf, **en silence** : c'est-à-dire précisément ce que le champ `MTIME`
existe pour empêcher, user-mode-linux refusant un *backing file* dont le `mtime` a bougé. Les
projets déjà faits avec ces images ne se seraient plus ouverts, et rien n'aurait échoué.

Le `sum(1)` des trois images est resté celui que leur nom annonce (`18474`, `08367`, `39212`) :
les octets n'ont pas bougé, seule l'horodate. Les `mtime` ont donc été **restaurés** depuis le
champ que le `.conf` déclare.

### 2. Une garde, qui nomme son remède au lieu de réparer

Le script **refuse** désormais d'empaqueter une image déjà publiée dont le `mtime` disque
diffère du `MTIME` de son `.conf`, en nommant le `touch -d @<MTIME>` qui le corrige. Ce n'est
pas une réparation automatique, et c'est délibéré : réécrire un `mtime` n'est juste que si les
**octets** n'ont pas changé, ce que seul l'appelant peut trancher — une image dont le contenu a
changé doit être republiée **sous un autre nom**, son nom *étant* son `sum`. Le mode
« instantané » n'a pas besoin de cette garde : il écrit le `.conf` à partir du disque, l'écart
y est impossible par construction.

### 3. La métadonnée, enfin exacte

`MD5SUM=e7b651d1…` → **`afe9d7e8cd5d4b978fa9079ebd7c98e9`**, dans les **deux** `.conf` (machine
et routeur : c'est le même fichier d'images, donc le même digest), puis republication de la
famille guignol **entière**, puisque tout en dérive :

- `filesystems_machine-guignol-18474.tar.xz` et `filesystems_router-guignol-18474.tar.xz`
  (image à `2017-06-09 15:01` dans l'archive, `SUM`/`MTIME` intacts) ;
- `marionnet-fs-guignol_18474_all.deb` et `marionnet-fs-guignol-18474-1.noarch.rpm`, dépliés du
  tarball corrigé — leurs `.conf` embarqués portent le nouveau digest, leurs images le `mtime`
  de 2017 ;
- les **trois** catalogues réécrits chacun par son écrivain : `SHA256SUMS` (35 artefacts, ligne
  par ligne remplacée avec le `--force` borné de l'épisode 9b), `Packages`/`Release`, et
  `repodata/`.

### 4. Le commentaire du chooser, remis à jour sans changer sa conception

`image_integrity_verdict` (`bin/scripts/marionnet-install.sh`) rend compte des **deux** champs
séparément plutôt que d'un verdict unique : la raison en était guignol, elle n'y est plus.
La forme, elle, reste — la situation qu'elle traite n'a pas disparu : un `.conf` publié il y a
longtemps, ou reçu d'ailleurs, peut porter le digest périmé d'une image par ailleurs conforme, et
**rien dans Marionnet ne lit `MD5SUM`** (`bin/disk.ml` le déclare et ne le consulte jamais). Seul
le commentaire a changé, en datant le fait.

### Prouvé (2026-08-31)

- La garde **refuse** (rc 2) l'image telle qu'elle était avant restauration, en nommant sa valeur
  attendue, sa valeur disque et la commande de remède.
- Après restauration et correction : les 2 tarballs portent l'image à `1497013276`, `SUM=18474`,
  `MD5SUM=afe9d7e8…` ; `md5sum` de l'image extraite = ce champ ; `sha256sum -c SHA256SUMS` passe
  sur les **35** artefacts.
- Le `.deb` et le `.rpm` de données, inspectés (`dpkg-deb`, `rpm -qplv` + `rpm2cpio` dans
  `fedora:42`), portent le même `.conf` et la même horodate d'image.
- `dune build` rc 0 (le script est embarqué dans le binaire par `INCLUDE_AS_STRING`), et le banc
  réseau `bin/scripts/marionnet-install.sh.bench/run.sh` : **68 PASS, 0 FAIL** sur
  `debian:trixie-slim`.

### Restes

L'installation locale `/usr/local/share/marionnet/filesystems/*guignol*.conf` porte encore
l'ancien digest : c'est une machine installée, pas une source de publication, et le champ est
inerte — à corriger d'un `sed` root le jour où l'on y touche. Par ailleurs
`Makefile.d/release.deb.sh` n'est pas exécutable (664) là où ses cinq voisins le sont ; le
`Makefile` l'appelle par `bash`, donc rien n'échoue.

---

## Épisode 24 (2026-08-31) — le dépôt : `www.marionnet.org` est revenu, et le catalogue décide de ce qui monte

Point **(5)** de la feuille de route du § 5 bis — le premier point de ce chantier qui ait
jamais été **bloqué par l'extérieur**, et le seul. L'épisode s'ouvre sur une mesure qui
renverse sa propre prémisse.

### 1. La prémisse était fausse : le serveur est revenu

Toutes les notes depuis l'épisode 3 portent la même mention — *bloqué tant que
`www.marionnet.org` est en panne*. Elle a été **vérifiée avant d'être crue**, comme le veut
la reprise d'un chantier long, et elle ne tient plus :

| Ce qu'on suppose | Ce qui est mesuré (2026-08-31) |
|---|---|
| le site est en panne | `https://www.marionnet.org/` répond **200** |
| on ne sait pas y déposer | `ssh marionnet` répond ; `/home/marionnet/site/download/` existe |
| le listing est peut-être autre chose qu'Apache | **Apache/2.4.18 (Ubuntu)**, `FancyIndexing` — exactement ce que le banc de l'épisode 7 imitait |
| les liens seront peut-être servis en 404 | `/download/Marionnet.ova` **est** un lien, et il est servi (206) |
| il faudra peut-être un outil de plus là-bas | `rsync`, `tar`, `xz`, `sha256sum`, `gpg` sont présents |

Deux constats de cette reconnaissance commandent le reste. Le premier est une **contrainte** :
le serveur n'a que **15 Gio libres** sur 39. Le second est une **conception** que le banc de
l'épisode 7 avait devinée juste : le serveur est bien un Apache à `mod_autoindex`, si bien
que le **repli** de l'installeur (lire le listing quand `SHA256SUMS` manque) est un vrai
chemin de production et non une hypothèse de banc.

### 2. Le septième script n'est pas un publieur

`Makefile.d/upload.www.marionnet.org.sh` (cible `make release-upload`) rejoint les six
autres, mais il en diffère par nature, et c'est la règle de conception de tout le fichier :
les six **fabriquent** un répertoire de release, celui-ci ne fait que le **porter**. D'où
l'invariant qu'il s'impose : **ce script n'écrit rien dans un répertoire de release**. Chaque
fichier qu'il dépose a exactement un écrivain ailleurs, et en ajouter un second ici est
précisément la manière dont deux catalogues se mettent à diverger (épisode 8) ou dont un
index se périme sous une empreinte enregistrée pour lui (épisode 9b).

### 3. Le catalogue décide de ce qui monte — et cette fois ce n'est pas une élégance

C'est le pendant exact de l'invariant de l'épisode 8 : `SHA256SUMS` n'est pas un fichier
d'intégrité qui liste des noms par commodité, il **est** la liste de ce dont une release est
faite. Le script lit cette liste, et **n'envoie rien d'autre**.

Ici, la règle ne fait pas qu'être juste, elle **évite une panne**. Un répertoire de release
contient aussi l'**état de travail du publieur** — les images nues et leurs `.conf`, dont les
tarballs ont été tirés :

| | Taille |
|---|---|
| le répertoire `1.0.x` sur disque | **11 Gio** |
| ce que `SHA256SUMS` catalogue | **3,87 Gio** (35 artefacts) — puis **1,6 Gio** (31), cf. § 10 |
| les images nues, que personne ne télécharge (`machine-debian-trixie-39212` : 5,4 Gio) | 7,3 Gio |
| place libre sur le serveur | **15 Gio** |

Déposer « le répertoire de release » aurait donc échoué, et échoué **à mi-chemin** — après
avoir passé des heures à envoyer une image de 5,4 Gio qu'aucun consommateur ne demande
jamais, l'installeur téléchargeant des **tarballs**.

### 4. `rsync`, là où l'ancêtre faisait `tar | ssh`

L'aïeul (`useful-scripts/BACKUP/marionnet_from_scratch.install_on_site`) déposait par
`tar cf - … | ssh marionnet tar -C … -xf -`. Deux raisons qu'il n'avait pas l'imposent
aujourd'hui : une release fait **3,87 Gio à travers un `ProxyJump`**, donc un dépôt
interrompu doit **reprendre** au lieu de recommencer ; et la republication est idempotente
**par le nom** (épisode 8), donc ce qui est déjà là et identique ne doit pas repartir.

`--partial-dir` est la moitié prudente de la première raison. Un artefact tronqué sous le
**bon** nom serait le pire des cas — l'installeur le téléchargerait, trouverait l'empreinte
en désaccord et le **retirerait** (épisode 8), en signalant une corruption qui n'est qu'un
envoi interrompu. **Mesuré, et l'énoncé initial était trop généreux** : ce qui garantit qu'un
nom réel n'est jamais tronqué, ce n'est pas `--partial-dir`, c'est que `rsync` écrit d'abord
sous un nom temporaire (`.<nom>.XXXXXX`) et ne renomme **qu'à la fin**. `--partial-dir`, lui,
n'ajoute que le *rattrapage* : il ne s'exerce que si le récepteur a le temps de ranger son
fichier partiel, ce qu'une coupure brutale de la connexion ne lui laisse pas — l'interruption
volontaire du 2026-08-31 a laissé un `.filesystems_…tar.gz.VUPZvk` de 150 Mio à l'endroit
même, à retirer à la main. La garantie qui compte tient donc sans lui ; ce qu'il apporte, la
reprise, est conditionnel, et il faut le dire ainsi.

`-rlt` et **non** `-a` : `-a` implique `-pgo`, c'est-à-dire demander la préservation du mode,
du propriétaire et du groupe du packageur sur une machine où cet utilisateur n'existe pas ;
les fichiers étant des données publiques, les modes sont **énoncés** (`--chmod=D755,F644`).
`-t` est gardé, et ce n'est pas cosmétique : c'est lui qui fait dire vrai au listing Apache —
le catalogue **de repli** de l'installeur — sur la date de publication d'un artefact.

### 5. La preuve se prend sur le serveur

Après le transfert, `sha256sum -c SHA256SUMS` tourne **dans le répertoire distant**. Le
catalogue ayant voyagé avec les artefacts, le même fichier qui a dit quoi envoyer dit s'ils
sont arrivés — et la vérification ne coûte **aucune bande passante**, le serveur lisant son
propre disque. C'est la mesure pour laquelle l'épisode existe : un transfert qui se déclare
réussi n'est pas un dépôt intact.

Symétriquement, le répertoire local est vérifié **avant que quoi que ce soit ne parte** : on
ne dépose pas ce qu'on n'a pas contrôlé, et une empreinte prise ici coûte quelques secondes
et transforme « le dépôt est corrompu » en une question qui a une réponse.

### 6. Les extras sont nommés, jamais retirés

Un fichier présent là-bas et absent du catalogue est **signalé** et laissé en place ;
`--prune` le retire, et seulement si on le demande. Même posture que la garde de `mtime` de
l'épisode 23 : nommer le remède plutôt que l'appliquer. Un `rsync --delete` par défaut
supprimerait sans un mot une release plus ancienne que quelqu'un a posée exprès.

### 7. Deux points d'entrée stables, parce qu'une ligne `sources.list` est épinglée

L'épisode 13 avait noté le défaut sans le corriger : `deb … /download/marionnet-install.sh/1.0.x/ ./`
**nomme une série**, donc ouvrir `1.1.x` obligerait à éditer chaque machine ayant jamais
installé Marionnet. Le correctif appartient au serveur : `download/apt` et `download/rpm`,
deux liens vers la série courante, si bien que changer de série est **un `ln -sfn` ici et rien
du tout là-bas**. Apache suit les liens sur cet hôte (mesuré). Les deux pointent le **même**
répertoire, et ce n'est pas un doublon : **trois catalogues y cohabitent** (`SHA256SUMS`,
`Packages`, `repodata/` — épisode 18), donc ce répertoire *est* réellement les deux dépôts ;
seul le vocabulaire du lecteur diffère. Les cibles relatives sont voulues — un
`/home/marionnet/…` absolu dans la racine documentaire publierait aussi le répertoire personnel
du serveur dans le listing.

### 8. L'installeur est publié sous ses **deux** noms

`bin/scripts/marionnet-install.sh` décide de ce qu'il est en regardant `$0` (épisode 16) :
sous le nom `marionnet-get-images` il est le chooser d'images et refuse `--binary`. N'en
publier qu'un rendrait la commande documentée `marionnet-get-images` **inobtenable** — celui
qui enregistre le fichier sous ce nom obtient bien le chooser, encore faudrait-il qu'il le
sache. Le second nom est un **lien** et non une copie : deux copies d'un script qui se
reconnaît à son `$0` sont deux choses à tenir en phase. Il va dans le **parent** du
répertoire de série, là où siège encore le `marionnet_from_scratch` de l'ancêtre : c'est le
seul fichier dont l'URL doit survivre à toutes les séries.

### 9. La signature : câblée, non armée — et la raison n'est pas la paresse

C'est la seule question que le § 5 bis laissait ouverte pour cet épisode. `--sign KEYID`
produit les `InRelease` et `Release.gpg` qu'attend apt ; sans lui le dépôt reste
`[trusted=yes]`, ce qu'écrit `release.apt.sh` aujourd'hui et ce que **33 cas verts** ont
mesuré (épisode 15b). Décider de signer, c'est décider **trois** choses, et une seule est du
code :

1. **la signature elle-même** — une dizaine de lignes, **éprouvées** contre une clef jetable ;
2. la **garde de la clef privée** : une clef engendrée sur un portable de développement, sans
   phrase de passe pour qu'un script s'en serve sans surveillance, ne protège rien de ce
   qu'elle prétend protéger ;
3. la **distribution de la clef publique**, qui est celle qui décide si tout le reste vaut
   quelque chose. `signed-by=` n'est une promesse que si la clef atteint l'utilisateur par un
   canal **autre** que le dépôt qu'elle signe. Publier la clef à côté des paquets et dire
   d'aller la chercher là prouve exactement ce que https prouve déjà — que le serveur n'a pas
   été usurpé — et rien du tout sur qui a écrit les paquets.

Les points 2 et 3 ne sont pas des questions sur ce script, donc il ne les tranche pas. À
noter que la signature nous appartient tout de même, et que cela **n'enfreint pas** la règle
d'un seul écrivain : `Release` dit ce que le dépôt **contient** et appartient à l'indexeur,
`Release.gpg` dit **qui en répond** et appartient à qui dépose — ce script.

### 10. Une release ne publie plus qu'une seule forme : `.tar.xz`

Le premier dépôt réel a été **interrompu en cours de route**, sur une remarque de l'auteur, et
elle porte : le répertoire publiait **les deux formes** de chaque gros artefact,
`.tar.gz` *et* `.tar.xz`. Ce n'est pas un défaut du dépôt, c'en est un de la **release** —
un reste d'avant l'épisode 3, qui avait mesuré le facteur 4 et fait de `xz` le défaut sans
retirer les `.gz` déjà là.

| | |
|---|---|
| ce que le catalogue annonçait | **35** artefacts, **3,87 Gio** |
| dont des `.tar.gz` doublant un `.tar.xz` du même nom | 4 fichiers, **2,16 Gio** |
| ce qu'il annonce désormais | **31** artefacts, **1,6 Gio** |

Plus de la **moitié** du dépôt était donc la seconde compression des mêmes octets. Le retrait
est sans conséquence pour le consommateur, et ce n'est pas un raisonnement mais une mesure :
`artifact_format` (`bin/scripts/marionnet-install.sh`) retient la forme préférée **ou
l'autre**, si bien qu'un `--gz` joué sur le catalogue allégé liste les 6 artefacts de données
en `.tar.xz`, colonne `SUM` à `yes`, **au lieu d'échouer** ; et `xz-utils` est une dépendance
d'exécution **déclarée** depuis l'épisode 9b, donc aucune machine cible n'est démunie.

**Le geste, lui, illustre la règle du seul écrivain** : les 4 fichiers ont été supprimés du
répertoire, et c'est `make release.sha256sums` qui a **retiré leurs lignes de lui-même**
(*dropping the line of a file which is no longer there* ×4, `31 kept, 4 dropped`). Le
catalogue n'a pas été édité à la main — il ne l'est jamais.

**Une garde en est sortie**, et elle appartient au déposeur parce que c'est lui qui paie : le
catalogue décidant de ce qui monte, une redondance *dans* le catalogue devient une redondance
*sur le fil*, multipliée par le temps qu'elle prend. Avant tout transfert, le script nomme
désormais les artefacts catalogués sous **les deux formes** et rappelle le remède — supprimer
le `.gz` du répertoire, laisser le catalogueur se corriger. Nommer, pas réparer : le catalogue
a un seul écrivain, et ce n'est pas lui. Discriminance mesurée dans les deux sens : muette sur
le catalogue à 31 lignes, parlante sur un répertoire fabriqué qui reproduit le cas d'avant.

### 11. Le défaut que le premier run à blanc a montré

`--dry-run` **créait le répertoire de série** qu'il ne faisait que feindre de remplir : le
`mkdir -p` distant n'était pas gardé, et `rsync` rendait ensuite compte d'une destination que
le run lui-même venait de fabriquer. C'est la même famille de défauts que les trois précédents
du chantier (épisodes 19, 20b, 20c) : **juger par autre chose que ce qu'on mesure**. Un essai
à blanc dont on ne peut pas dire qu'il n'a rien changé n'est pas un essai à blanc. Corrigé, et
vérifié par la négative : après le second run, le serveur ne portait toujours aucun
`marionnet-install.sh/`.

### Prouvé (2026-08-31)

- **Reconnaissance** : `https://www.marionnet.org/` **200** ; `ssh marionnet` répond,
  `/home/marionnet/site/download/` existe, **15 Gio libres** sur 39 ; **Apache/2.4.18
  (Ubuntu)**, `FancyIndexing` ; `/download/Marionnet.ova` est un **lien** et il est servi
  (206) ; `rsync`, `tar`, `xz`, `sha256sum`, `gpg` présents là-bas.
- **Essai à blanc** : 36 chemins, 1,6 Gio annoncés, et le serveur **inchangé** — vérifié par
  la négative, aucun `marionnet-install.sh/` n'existait après le run.
- **Dépôt** : `1,70 Gio` envoyés à ~600 kio/s (le `ProxyJump` LIPN est le facteur limitant,
  pas le serveur), puis **la preuve prise sur le serveur** : *the server holds the 31
  catalogued artefacts, whole and intact*. **Aucun extra** signalé.
- **Idempotence par le nom** : le second passage envoie **1,63 Kio** au lieu de 1,70 Gio
  (`speedup 1 033 204`) — la republication ne renvoie que ce qui a changé.
- **Points d'entrée** : `apt/SHA256SUMS` 200 (3 250 o, **identique à l'octet** au fichier
  déposé), `rpm/repodata/repomd.xml` 200, `apt/Packages.gz` 200 ; listing Apache à
  **36 entrées** (le repli du catalogue fonctionne aussi).
- **L'installeur sous ses deux noms** : `marionnet-install.sh` et `marionnet-get-images`
  répondent 200, **48 097 o** l'un comme l'autre.
- **Bout en bout, contre le vrai serveur** : `marionnet-install.sh --from
  https://www.marionnet.org/download/apt --fetch-only --binary --list` liste les **14**
  artefacts logiques, colonne `SUM` à `yes` partout, et retient `r923` (`chosen`). C'est la
  **jambe https** du point (6) de la feuille de route, obtenue en passant.
- **apt, dans une `debian:13-slim` nue** : `apt update` lit `Release` (535 o) et `Packages`
  (2 417 o) **à travers le lien stable**, `apt-cache policy` voit les **4** paquets, et
  `apt-get install -s marionnet` résout l'application (`Marionnet:1.0.x`) avec ses
  dépendances Debian. Le point d'entrée stable n'est donc pas une intention.
- **Signature** : plomberie éprouvée **à part**, sur une clef jetable détruite depuis —
  `InRelease` (clearsign) et `Release.gpg` (détachée, armée) vérifient tous deux
  (*Bonne signature*). Rien n'est signé dans la release.

### Restes

- **La signature n'est pas prise**, par décision argumentée (§ 9) : ce qui manque n'est pas
  du code mais la **garde** de la clef privée et surtout sa **distribution hors bande**. Tant
  que ce n'est pas tranché, `[trusted=yes]` reste écrit dans la ligne `sources.list`.
- **Le canal `.deb` est en retard d'une révision** : le dépôt sert `marionnet` en `r920`
  quand le tarball et le `.rpm` sont en `r923` — l'épisode 22 avait rejoué la boîte et le
  canal RPM, pas `release-deb`. Un `make release-build-box WITH_DEB=1` suivi d'un
  `make release-upload` le rattrape ; rien n'est cassé, le dépôt est seulement moins récent
  que ses voisins.
- **`marionnet.repo` n'est pas publié** : il s'écrit avec l'URL, désormais connue —
  `make release-dnf BASE_URL=https://www.marionnet.org/download/rpm/`. Le déposeur le
  **signale** si le fichier existe sans nommer le point d'entrée stable.
- **Le débit** (~600 kio/s à travers le rebond) fait d'une release complète une affaire de
  trois quarts d'heure. C'est supportable parce que la republication est idempotente par le
  nom ; ce ne le serait plus si l'on reprenait l'habitude de publier deux formes.
- Les anciennes URLs de `download/marionnet_from_scratch/` ne sont **pas** redirigées vers
  les nouvelles (décision du § 6, encore à faire) : c'est de la configuration Apache, donc
  la suite naturelle de cet épisode côté serveur.

---

## Épisode 25 (2026-09-01) — une release n'est pas un journal de build

Épisode né d'une question de l'utilisateur en regardant le répertoire déposé la veille :
*« sont-ils vraiment tous utiles ? »* — non, et c'est un défaut de l'épisode 24. Il avait
appliqué *le catalogue décide de ce qui monte* sans redemander si le catalogue avait raison,
c'est-à-dire l'erreur exacte que l'affaire des `.tar.gz` venait de lui apprendre **une heure
plus tôt, dans le même épisode**.

### 1. Ce que le répertoire annonçait vraiment

| | publié | utile | périmé |
|---|---|---|---|
| tarball `marionnet_trunk-r*` | **8** révisions | 1 | 7 (**50 Mio**) |
| `.deb marionnet_0~trunk+r*` | **4** | 1 | 3 (**22 Mio**) |
| `.rpm marionnet-0~trunk+r*` | **5** | 1 | 4 (**33 Mio**) |

105 Mio de sous-produits d'une seule journée d'épisodes (9a→23). **Le poids est le moindre
problème** :

- `Packages` offrait à apt **4** versions de `marionnet`, `repodata/` en offrait **5** à dnf.
  Un `apt install marionnet=0~trunk+r913` rendait donc, en toute légitimité, une application
  **d'avant le correctif de l'épisode 21** — l'index la proposait.
- **5 des 8 tarballs étaient d'avant le plancher** (`glibc2.39`, compilés sur le portable et
  non dans la boîte de l'épisode 20) : refusés sur Debian 12, donc servis pour rien.
- Le `--list` de l'installeur affichait 7 lignes `superseded` avant la bonne.

Le `--multiversion` de `release.apt.sh` n'est pas en cause : il existe pour qu'une révision
puisse en **remplacer** une autre sans trou. Huit révisions ne sont pas un remplacement, c'est
une accumulation.

### 2. Une garde qui nomme, comme celle des deux formes

Le déposeur savait nommer une redondance de **formes** (`.gz` doublant un `.xz`) ; il ne savait
pas nommer une redondance de **révisions**. Il le sait désormais, et **il ne retire rien** :
combien de révisions une release garde n'est pas sa décision (règle du seul écrivain, épisode
24). Il nettoie en revanche le `.rsync-partial/` vide qu'il laissait derrière lui — c'est la
seule chose du serveur dont il soit propriétaire, puisqu'il est le seul à la créer.

### 3. La fenêtre : la dernière icône de la planète était hors champ

Défaut d'usage signalé en séance : la fenêtre principale n'est pas assez haute pour montrer la
**dernière icône de la barre des composants** — la *planète*, c'est-à-dire le menu à trois
entrées (*Gateway* / *NAT bridge* / *LAN bridge*) que le chantier `modernisation-world-bridge`
a construit. Une nature accessible par aucun geste visible n'existe pas pour l'utilisateur.

**La piste indiquée menait au vestige** : `bin/gui/gui.xml` (glade-2, `default_height` 690) est
listé comme vestige par le `CLAUDE.md` du projet, et **il n'est pas chargé** — `bin/gui.ml`
lit `gui_glade3.xml`, dont la `default-height` valait **840**. L'éditer n'aurait rien changé,
et c'est précisément le piège que le `CLAUDE.md` signale.

**840 → 860** (et la largeur par défaut 340 → 350), la discriminance étant mesurée dans les
deux sens, capture d'écran à l'appui : à **840** la dernière icône visible est le **nuage**, la
planète est **absente** ; à **860** elle s'affiche entière. La fenêtre fait 1102 × 860 sur cet
écran (1440 de haut, donc aucune contrainte du gestionnaire de fenêtres).

**Pourquoi 860 suffit là où 840 échoue, et pourquoi 900 n'apportait rien** : la colonne
d'icônes **ne grandit pas** avec la fenêtre — mesuré, la planète occupe la même position à 860
et à 900 — le surplus de hauteur allant au canevas. Il ne manquait donc pas « une icône de
marge » mais les quelques pixels qui séparaient la dernière icône du bord. La première valeur
essayée, 900, était plus large que nécessaire ; 860 est le chiffre rond qui suffit.

### 4. `make revno`, et pourquoi la règle n'est pas dans le `Makefile`

`bzr revno` donnait le numéro de révision d'un coup ; depuis la conversion, il fallait le
connaître par cœur. La cible existe désormais — mais elle **demande** le numéro à
`bin/meta.ml.maker.sh --print-revision` au lieu de le recalculer. Ce n'est pas de la
préciosité : ce script **est** l'endroit où la règle vit (git `rev-list --count`, repli bzr
tant que `.bzr` est là), et ce numéro est celui dont **tout artefact publié porte le nom**
(`marionnet_trunk-r<N>_…`, `0~trunk+r<N>`). Écrire `git rev-list --count HEAD` dans le
`Makefile` aurait fait une seconde source de vérité, et les deux se seraient séparées le jour
où le repli compte. Même forme que le `--print-series` de
`filesystem.prepare-snapshot-to-publish.sh`.

### 5. Ce qui n'a PAS été retiré, et pourquoi

L'abandon des `.tar.gz` est **définitif côté publication** (aucun n'est plus produit ni
déposé), mais l'option `--gz` de `bin/scripts/marionnet-install.sh` et le `--gzip` des deux
producteurs **restent**. La raison est mesurable : `download/marionnet_from_scratch/0.98.x/`,
toujours servi, ne contient **que** des `.tar.gz` (`filesystems_guignol.tar.gz`,
`kernels_linux-3.2.64-ghost.tar.gz`…). Un installeur qui ne saurait plus lire cette forme ne
saurait plus lire les anciennes séries ; et retirer le drapeau du producteur tout en gardant
celui du consommateur serait incohérent. L'abandon porte sur ce qu'on **publie**, pas sur ce
qu'on **sait lire**.

### 6. Le rebond n'aime pas les rafales — et le déposeur n'ouvre plus qu'une connexion

Le premier `--prune` réel a **échoué à mi-chemin**, et le défaut était dans sa forme : il
ouvrait **une connexion ssh par fichier**. Dix-sept connexions coup sur coup **à travers le
rebond LIPN** (`ProxyJump lipn-ssh`), et le rebond a fait ce pour quoi il est là —
`kex_exchange_identification: Connection reset by peer`, puis un **back-off de plusieurs
minutes** pendant lequel plus rien n'atteignait le serveur. Treize fichiers avaient été
retirés, quatre non.

Deux corrections, dont la seconde vaut pour tout le script :

1. `--prune` retire toute la liste en **un seul appel** (`rm -rf -- a b c`), les noms venant
   du serveur étant toujours passés par `printf %q`.
2. Le script n'ouvre plus **qu'une connexion maîtresse** (`ControlMaster=auto`,
   `ControlPersist`), partagée par ses ~10 appels **et par `rsync`** (`-e`). C'est la vraie
   réponse : un dépôt fait naturellement une douzaine d'appels courts, ce qui, vu du rebond,
   ressemble exactement à ce contre quoi il se défend. Le run y gagne aussi le temps d'autant
   de poignées de main. Le chemin du socket est gardé **court** à dessein — un socket unix
   plafonne vers 104 octets, là où les répertoires de travail de ce projet sont bien plus
   longs.

Un piège de bash au passage : bash ne garde **qu'un seul** gestionnaire `EXIT`, donc les
`trap 'rm -f …' EXIT` posés plus bas **remplaçaient silencieusement** celui qui ferme la
connexion maîtresse. Un `cleanup` unique, désormais.

### Prouvé (2026-09-01)

- **Fenêtre** : à `default-height` **840**, la dernière icône de la barre est le **nuage** et
  la planète est **absente** ; à **860**, elle s'affiche entière (captures des trois états —
  840, 860, 900 — fenêtre 1102 × 860, écran 3440 × 1440). La planète est au **même endroit** à
  860 et à 900 : la barre ne grandit pas avec la fenêtre, donc 900 n'achetait rien de plus.
  La bordure de l'écran d'accueil passe par ailleurs de 10 à 24 px (`bin/splash.ml`).
- **`make revno`** répond **926** avant le commit de l'épisode, **927** après —
  `bin/meta.ml.maker.sh --print-revision` étant la seule source.
- **Chaîne rejouée en entier à r927** : `make release-build-box WITH_DEB=1` (tarball 7,1 Mio
  + `marionnet_0~trunk+r927_amd64.deb`, dans la boîte plancher `debian:12`), puis
  `make release-rpm` (**rien de compilé**, le tarball publié est déplié →
  `marionnet-0~trunk+r927-1.x86_64.rpm`).
- **Ménage** : 17 révisions périmées retirées localement, et les **trois** catalogues
  réécrits par leurs écrivains — `SHA256SUMS` **17 artefacts** (`17 dropped`), `Packages`
  **4 paquets**, `repodata/` **6 paquets**, plus `marionnet.repo` enfin écrit avec l'URL
  stable (`--base-url https://www.marionnet.org/download/rpm/`).
- **Dépôt** : 23,3 Mio envoyés (le reste étant déjà là, à l'identique), *the server holds the
  17 catalogued artefacts, whole and intact*, puis élagage des 17 extras. Le répertoire
  distant est passé de **37 à 23 entrées**, 1,5 Gio, sans `.rsync-partial`.
- **Ce que voit l'utilisateur, contre le vrai serveur** : l'installeur liste **7** lignes, une
  par artefact, `r927 chosen` et plus une seule `superseded` ; `apt-cache madison marionnet`
  dans une `debian:13-slim` nue n'offre plus qu'**une** version (`0~trunk+r927`) ; et
  `dnf install marionnet` sur `fedora:42`, après avoir récupéré `marionnet.repo` **à
  l'adresse stable**, résout `marionnet` + `vde2` + `uml-utilities` du même dépôt.
- La garde des révisions, parlante avant le ménage (17 nommées), est **muette** après.

---

## Épisode 26 (2026-09-01) — un seul geste, et le propriétaire de la rétention

Demande de l'auteur : une cible unique à lancer soi-même pour mettre à jour le local **et** le
site à la révision courante. Deux réponses, dont une négative.

### 1. Pas de script de regroupement — et la série ne se code pas dans un nom

Le nom proposé, `release-for-series-1.0.x-and-upload`, **figeait la série** : elle est déjà
**dérivée** (`PUBLICATION_SERIES`, lue de `META` par le script qui possède la règle), si bien
qu'un nom la nommant obligerait à créer une seconde cible le jour de `1.1.x`. La cible est donc
**`make release-and-upload`** — la famille (`release-binary`, `release-deb`, `release-rpm`,
`release-apt`, `release-dnf`, `release-upload`, `release-build-box`) et, surtout, **le nom dit
qu'elle dépose**. `make release` eût été plus court, mais se lit comme *fabrique une release*
alors que celle-ci **la met en ligne** : la surprise aurait été publique.

**Aucun script dans `Makefile.d/`** pour ce regroupement, et c'est délibéré : la chaîne est
linéaire, chacun de ses maillons est déjà une cible, et elle n'a **aucune connaissance propre**.
Un script n'aurait fait que ré-emballer `make`, en ajoutant un endroit où l'ordre peut diverger.

### 2. Ce qui manquait vraiment : personne ne possédait la rétention

L'épisode 25 a supprimé 17 révisions périmées **à la main**, et sa garde savait les *nommer*
sans avoir le droit de les retirer — le déposeur ayant pour règle de conception de n'écrire
**rien** dans un répertoire de release. La règle « quelles révisions sont périmées » existait
donc, mais chez quelqu'un qui ne pouvait pas s'en servir, et en un exemplaire recopié.

D'où **`Makefile.d/release.retention.sh`** (cible `make release-retention`), huitième script de
la famille, qui **possède** cette question : *combien de révisions de l'application une release
garde-t-elle ?* Défaut **1**, `KEEP=2` pour déroger. Et le déposeur ne recalcule plus rien : il
**demande** (`--print-superseded`). Une règle, un propriétaire, deux lecteurs — le doublon que
l'épisode 25 avait introduit disparaît. Avoir un avertissement et une suppression en désaccord
sur le sens de « périmé » serait pire que n'avoir aucun avertissement.

**Trois choses qu'il ne fait pas.** Il ne regarde **que l'application** : un noyau se versionne
`6.12.95`, une image par son `sum`, il n'y en a donc jamais deux, et les republier leur
donnerait un `mtime` neuf — ce qu'UML vérifie (épisode 23). Il ne **touche pas au serveur** :
ce qu'il retire ici devient simplement un *extra* là-bas, que `make release-upload PRUNE=1`
retire ensuite — décider qu'une release n'offre plus `r913` et aller dans un serveur public
sont deux gestes, pas l'effet de bord d'une commande. Et il ne **réécrit aucun catalogue
lui-même** : il appelle les trois écrivains, règle payée à l'épisode 24.

### 3. Deux contrôles préalables, tous deux payés par la mesure

`make release-and-upload` refuse de commencer si :

- **l'arbre de travail n'est pas propre** — `release.build-box.sh` clone **HEAD** (épisode 20),
  donc du travail non committé ne fait pas échouer la compilation : il **ne part pas**, en
  silence, et la release porte alors le nom d'une révision dont elle n'a pas le contenu ;
- **`CONFIGME.choice` pointe sur la configuration *testing*** — `release.binary.sh` la refuse
  (le préfixe compilé serait le switch opam, épisode 9a). Mieux vaut le dire à la première
  seconde qu'après dix minutes de compilation.

Ni l'un ni l'autre n'est contournable **ici**, à dessein : chacun a une échappatoire explicite
sur le script qui le possède, et y recourir doit être un acte délibéré, pas une variable posée
sur une chaîne de quatre maillons.

### Prouvé (2026-09-01)

- `release.retention.sh --print-superseded` sur un répertoire fabriqué (4 tarballs, 3 `.deb`,
  2 `.rpm`, plus un noyau et une image) : **6** noms à `KEEP=1`, **3** à `KEEP=2`, et **jamais**
  la révision la plus récente ni un artefact de données — vérifié par comptage.
- Sur le vrai répertoire, déjà rangé à l'épisode 25 : **rien à retirer**, et la garde du
  déposeur est muette. Plus aucune occurrence de `revision_of` dans le déposeur.
- Contrôle préalable « arbre sale » : **rc 2**, nomme les fichiers en cause. Contrôle
  « configuration testing » : passe sur `CONFIGME`, **refuse** sur `CONFIGME.testing.sh`
  (éprouvé dans les deux sens, symlink restauré).
- `make -n release-and-upload` déroule les quatre maillons dans l'ordre ; `dune build` rc 0.
