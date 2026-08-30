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
│       ├── kernels_linux-6.12.95.tar.gz
│       ├── kernels_linux-6.12.95-i386.tar.gz
│       ├── machine-debian-trixie-<SUM>{,.conf,.relay,_variants/}
│       ├── filesystems_machine-debian-trixie-<SUM>.tar.gz
│       ├── machine-debian-wheezy-08367{,.conf,.relay,_variants/}
│       ├── filesystems_machine-debian-wheezy-08367.tar.gz
│       └── filesystems_{machine,router}-guignol-18474.tar.gz  (.conf patchés inclus)
├── 1.0.x/
│   ├── binaries/               # Marionnet précompilé (par famille de distro/glibc)
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

### 3.2 Matrice canaux × publics

| Canal | Public privilégié | Contenu | Chantier |
|---|---|---|---|
| **Script v2** | non-Debian (guide), admins, repli universel | deps apt si Debian-like + binaire ou compilation opam + couples + conf | enfant `…-par-script` |
| **.deb + dépôt apt** | étudiant portable, salle TP Debian-like | `marionnet` (binaire+ressources), `marionnet-kernels-*`, `marionnet-fs-*` (découpage à décider) | enfant `…-par-paquet-deb` |
| **RPM** | Fedora/openSUSE | specs `RPMS/` modernisées | enfant `…-par-paquet-rpm` |
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
   Prérequis de tout canal. — **La FABRICATION locale des artefacts est faite** (images :
   épisode 3 ; noyaux : épisode 5) ; reste l'arborescence servie et le **dépôt** sur le
   serveur.
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
  (wheezy 560 Mo, trixie ~5 Go) restent dans `download/marionnet-install.sh/1.0.x/`, récupérées par
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
  Livrable : `useful-scripts/marionnet-install.sh`, germe du script v2, n'implémentant que son
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
  repli `curl`).

- **2026-08-30 — épisode 7 : le chemin réseau, mesuré sans le serveur.** L'épisode 6 laissait
  un trou nommé : « le chemin **réseau** est écrit, il n'est pas mesuré ». Il ne concerne que
  **deux lignes** — la branche `url` de `catalog_list` (listing Apache, noms lus dans les
  `href="…"`) et celle d'`artifact_stream` (`wget -q -O -`) — mais ces deux lignes *sont* ce
  qu'est un serveur de release. Plutôt que d'attendre le retour de `www.marionnet.org`, cet
  épisode **dresse le serveur** : un Apache en conteneur, un répertoire de release synthétique,
  et le script lancé depuis un **second** conteneur qui ne contient que Debian et le script.
  Livrable : `useful-scripts/marionnet-install.sh.bench/` (`run.sh`, `Dockerfile.server`,
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
