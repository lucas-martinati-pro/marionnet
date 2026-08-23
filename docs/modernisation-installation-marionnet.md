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
| `REQUIRED_PACKAGES_RUNTIME` | `vde2 graphviz uml-utilities xterm iproute2 sudo x11-xserver-utils xauth jq socat dnsmasq-base` (`bridge-utils` **retiré** le 2026-08-23) | **`Depends` du `.deb`** ; `Requires` du RPM ; couche runtime Docker ; script v2 `marionnet-install.sh` |
| `REQUIRED_PACKAGES_RUNTIME_I386` | `libc6:i386` | `Recommends` (ou `Suggests`) du `.deb` — voir ci-dessous |
| `REQUIRED_PACKAGES` | union des deux | cible historique `apt-dependencies` |
| `OPAM_PACKAGES` | `dune dune-site camlp4 camlp-streams inotify lablgtk3 lablgtk3-extras lablgtk3-sourceview3 conf-gtksourceview3` **`yojson base64`** | `make opam-dependencies` ; `Build-Depends` du `.deb` ; `BuildRequires` du RPM ; image de **build** Docker ; essai « toolchain système » (ép. 3) |

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
| `jq` | `bashbricks/bashbricks.sh` (module `Json_*`, **fichier installé**, sourcé par `bin/scripts/marionnet-{nat,lan}bridge.sh`) ; `useful-scripts/mrn-check` et `mrn-verify`, qui **refusent de démarrer** sans lui (`command -v jq \|\| die`) | `modernisation-world-bridge`, `pilotage-par-script` |
| `socat` | `useful-scripts/marionnet-ctl` (`socat - UNIX-CONNECT:<socket>`, garde `command -v socat \|\| die`) | `pilotage-par-script` |
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

### 2.4 ter Ce que l'installation ne pose pas : les clients du canal (constat 2026-08-12)

**Constat mesuré** (`grep -rn 'useful-scripts' Makefile Makefile.d/*.mk` : aucun résultat) :
**aucun** client du canal de contrôle n'est installé, par aucune cible. `install-final-as-root`
fait `dune install --prefix` puis copie `$(SHARE_DIR)/scripts/*` dans `$(PREFIX_INSTALL)/bin/` —
ce sont les scripts **invités** (`bin/scripts/`), pas ceux de `useful-scripts/`. Aujourd'hui, les
outils ne sont donc utilisables que **depuis un clone du dépôt**.

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

**À installer** (nommer chacun, l'inventaire n'est pas déductible du dossier — cf. § 2.5, où tout
est ignoré sauf une liste) :

| Fichier | Destination | Remarque |
|---|---|---|
| `useful-scripts/marionnet-ctl` | `$(PREFIX)/bin/` | le client |
| `useful-scripts/mrnctl` | `$(PREFIX)/bin/` | **lien** vers le précédent — nom court |
| `useful-scripts/mrn-check` | `$(PREFIX)/bin/` | vérificateur d'un `.mrn` |
| `useful-scripts/mrn2sh` | `$(PREFIX)/bin/` | **lien** vers `mrn-check` : le **nom implique `--to-bash`** |
| `useful-scripts/mrn-verify` | `$(PREFIX)/bin/` | vérificateur déclaratif d'un labo qui tourne (`.mrv`) |
| `useful-scripts/marionnet-completion.bash` | `/usr/share/bash-completion/completions/` (ou `$(PREFIX)/share/…`) | dessert `marionnet-ctl`, `mrnctl`, `mrn-check`, `mrn2sh`, `mrn-verify` |

> **RÉSOLU (partiellement) le 2026-08-21 — `useful-scripts/dune`.** Cinq des six fichiers du
> tableau ci-dessus, **plus `useful-scripts/marionnet-cleanup`**, sont désormais installés par
> **dune** : une stanza `install` neuve (`useful-scripts/dune`, patron `bashbricks/dune`) les pose
> dans `share/marionnet/scripts/`, que le `Makefile` **mirroir déjà** dans `$(PREFIX)/bin/` en les
> rendant exécutables (liens durs pour `install-final-as-root`, symboliques pour
> `install-for-testing`) — d'où **aucune ligne de `Makefile` à ajouter**. La voie « stanza dune »
> tranche donc l'alternative laissée ouverte plus bas.
> Ce qui a forcé la décision : Marionnet **nomme** `marionnet-cleanup` à l'écran depuis l'ép. 6 de
> `marionnet-todo-transverse`, et **le lance lui-même** depuis les deux boutons de cet
> avertissement (2026-08-21) — un programme qui dit à l'utilisateur de lancer une commande doit
> lui laisser cette commande sur le `PATH`.
> **Restent à faire ici** : la **complétion bash** (`marionnet-completion.bash` n'est pas une
> commande et ne va pas dans `bin/` — cf. la ligne du tableau), la déclaration de **`socat`** et
> **`jq`** comme dépendances **hôte** dans les paquets (`Depends`/`Requires`/image Docker), et le
> même travail pour la **documentation d'usage** (complément 2026-08-13 ci-dessous).
> Note sur les liens : dune installe `mrnctl` et `mrn2sh` en **copies**, ce qui préserve le
> comportement (les deux scripts lisent `${0##*/}`, jamais l'inode), mais ne dispense pas les
> paquets de poser de vrais liens s'ils préfèrent.

⚠️ **Les liens ne sont pas décoratifs** : `mrn2sh` est `mrn-check` sous un autre nom, et le script
lit `$0` pour en déduire son mode (`mrn2sh` ⇒ `--to-bash` implicite) ; `mrnctl` est le nom court
de `marionnet-ctl`. Une installation qui les **copie sous un autre nom**, ou qui n'en pose qu'un
seul, change le comportement. Poser des liens (symboliques ou durs), jamais renommer.

Pour la complétion, un seul fichier dessert les cinq noms (il finit par autant de `complete -F`) :
l'installer une fois et, si la distribution l'exige, créer des liens par nom de commande.

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
renvoie explicitement à `useful-scripts/marionnet-cleanup --purge-dirs` — le seul geste proposé à
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
> Il ne reste **10 fichiers suivis** : `dune`, `marionnet_from_scratch` (gardé comme pièce à
> conviction de l'autopsie § 2), `make_marionnet_bytecode_revno`, `marionnet-completion.bash` et
> les 6 exécutables installés. Quatre fichiers **versionnés** ont été retirés à cette occasion :
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
├── 1.0.x/
│   ├── couples/                # kernels + filesystems modernes (tar.gz, MTIME préservés)
│   │   ├── kernels_linux-6.12.95.tar.gz
│   │   ├── kernels_linux-6.12.95-i386.tar.gz
│   │   ├── filesystems_machine-debian-trixie-<SUM>.tar.gz     (+ .conf, variants)
│   │   ├── filesystems_machine-debian-wheezy-08367.tar.gz     (.conf patché + .relay inclus)
│   │   └── filesystems_{machine,router}-guignol-18474.tar.gz  (.conf patchés inclus)
│   ├── binaries/               # Marionnet précompilé (par famille de distro/glibc)
│   └── src/                    # tarballs sources du port dune (git archive)
├── apt/                        # dépôt apt signé (canal .deb)
├── rpm/                        # canal RPM
└── marionnet-install.sh        # script v2 (les anciennes URLs marionnet_from_scratch
                                #  restent servies avec un message de redirection)
```

Bénéfice immédiat : les tarballs de couples régénérés incluent les `.conf` patchés
(fin du « patch à rejouer si l'image est retéléchargée » des ép. 2-3 retro-compat).

### 3.2 Matrice canaux × publics

| Canal | Public privilégié | Contenu | Chantier |
|---|---|---|---|
| **Script v2** | non-Debian (guide), admins, repli universel | deps apt si Debian-like + binaire ou compilation opam + couples + conf | enfant `…-par-script` |
| **.deb + dépôt apt** | étudiant portable, salle TP Debian-like | `marionnet` (binaire+ressources), `marionnet-kernels-*`, `marionnet-fs-*` (découpage à décider) | enfant `…-par-paquet-deb` |
| **RPM** | Fedora/openSUSE | specs `RPMS/` modernisées | enfant `…-par-paquet-rpm` |
| **Docker** | démo rapide, environnements verrouillés | image VNC/noVNC XFCE (MarioNUM g3) avec Marionnet moderne sans daemon | enfant `…-par-docker` |
| **From source** | experts, distros exotiques, dev | opam switch 4.13.1 (chaîne actuelle documentée) | parent (doc INSTALL) |

Tous les canaux consomment les **mêmes couples** (`download/couples/`) et la **même
config** — factorisation au parent.

### 3.3 Outillage release commun (parent)

- `make release-couples` : tar.gz des couples installés/buildés (MTIME préservés, `.conf`
  patchés inclus) + dépôt ssh sur le serveur (germe : `install.last-built-couple.sh` +
  `marionnet_from_scratch.install_on_site`).
- `make release-binary` : build propre + `dune install --prefix` dans un staging +
  tarball binaire relocatable (question § 6) — base des canaux script v2 / .deb / RPM / Docker.
- `make release-src` : `git archive` de la série.
- Signature GPG des artefacts et des index (dépôt apt notamment).

## 4. Chantiers enfants candidats (essaimage au fil des épisodes)

1. `modernisation-installation-marionnet-par-script` — script v2 (périmètre : Debian-like
   bout-en-bout + mode guide ; réutilise deps § 2.4, binaire ou opam, couples, conf).
2. `modernisation-installation-marionnet-par-paquet-deb` — empaquetage .deb + dépôt apt
   signé sur marionnet.org.
3. `modernisation-installation-marionnet-par-paquet-rpm` — specs `RPMS/` ravivées.
4. `modernisation-installation-marionnet-par-docker` — image MarioNUM g3 passée au
   Marionnet moderne (sans daemon, base 24.04+), publication (registre à décider).

Le **parent garde** : l'autopsie (§ 2, close), la remise à niveau du serveur, l'outillage
release commun (§ 3.3), la doc INSTALL from-source, la cohérence inter-canaux et la
clôture des enfants.

## 5. Plan d'épisodes (parent) — ordre acté le 2026-07-19

1. **Remise à niveau du serveur** : arborescence `download/` cible (§ 3.1, série
   `1.0.x/`) + `make release-couples` + dépôt des couples modernes (6.12.95,
   6.12.95-i386, trixie, wheezy/guignol re-tarrés avec `.conf`/`.relay` patchés).
   Prérequis de tout canal.
2. **Outillage binaire** : `make release-binary`, staging `dune install --prefix` +
   tarball, test sur machine vierge (conteneur jetable). La relocatabilité est acquise
   (§ 6, point réglé) : le tarball embarque un `marionnet.conf` adapté si besoin.
3. **Essai toolchain système** (borné à une session, § 6) : tentative de build avec
   ocaml 4.14 + camlp4 4.14+1 + liblablgtk3-ocaml-dev d'apt, sans opam. Succès → le
   .deb devient source-buildable et le script v2 se simplifie ; échec → documenté, on
   en reste à opam (la levée du gel reste au chantier `marionnet-camlp4-ppx`).
4. **Essaimage des enfants, dans l'ordre** : `…-par-script` (déverrouille aussi le
   Dockerfile MarioNUM) → `…-par-paquet-deb` → `…-par-docker` → `…-par-paquet-rpm`.
5. **Doc INSTALL** moderne (from source + renvois canaux) ; ~~nettoyage des vestiges
   `useful-scripts/` (archivage explicite des strates historiques)~~ **fait le 2026-08-23**
   (épisode 2, § 2.5) ; clôture.

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
  (wheezy 560 Mo, trixie ~5 Go) restent dans `download/1.0.x/couples/`, récupérées par
  un outil dédié (commande type `marionnet-get-images`, proposée en postinst).
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
