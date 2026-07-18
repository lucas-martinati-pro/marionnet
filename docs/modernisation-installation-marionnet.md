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

### 2.5 Satellites de `useful-scripts/` (strates historiques)

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
5. **Doc INSTALL** moderne (from source + renvois canaux) ; nettoyage des vestiges
   `useful-scripts/` (archivage explicite des strates historiques) ; clôture.

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
