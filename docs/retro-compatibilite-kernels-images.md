# Chantier : rétro-compatibilité des vieux couples kernel/image UML

**Slug (commits, mémoire, grep)** : `marionnet-retro-compat-kernels-images`
**Objectif** : faire re-tourner les anciennes images invitées (debian-wheezy-08367,
guignol-18474, mandriva20100215), historiquement couplées à `linux-3.2.64-ghost`, sur un
hôte moderne (noyau ≥ 6.x), en s'appuyant sur un noyau UML récent compilé en **i386**.

## Contexte et diagnostic (étude du 2026-07-17)

### Symptôme

Sur l'hôte de dev/test (Kubuntu 24.04, noyau 6.8.0-134-generic), une VM
`linux-3.2.64-ghost` + wheezy se fige au boot juste après le montage de la racine :

```
wait_stub_done : failed to wait for SIGTRAP, pid = …, n = …, errno = 0, status = 0xb7f
```

précédé d'un dump « Stub registers » avec eip ≈ `0x100080` : le **stub SKAS0 segfaute**
(`0xb7f` = arrêt sur SIGSEGV). Logs de référence versionnés :
`uml/kernel/linux-3.2.64-ghost.with-debian-wheeze.boot-stucked-failure.log` et
`…command-launched-by-marionnet.log`.

### Diagnostic

- Repro CLI minimale hors GUI (COW jetable) : gel encore plus tôt (après « unknown
  partition table »), processus principal en **boucle CPU** (état R, wchan=0).
- **Insensible à `setarch i386 -R -L`** (ASLR désactivé + layout mmap legacy) → pas de
  parade « lanceur » simple. `vm.mmap_min_addr` (65536 < 0x100000) hors de cause.
- `strace -f` inutilisable pour aller plus fin : UML utilise ptrace pour lui-même.
- Pattern historique documenté (HOWTO UML, pratique netkit) : les vieux noyaux **invités**
  cassent quand l'hôte avance ; le remède standard est un invité récent, pas un réglage hôte.
- **Recompiler le 3.2.64 est une impasse** : le problème est dans le code du stub lui-même
  (pas dans sa compilation), et gcc moderne ne compile plus un arbre 3.2.

### Contrainte d'architecture

`linux-3.2.64-ghost` est un ELF **i386** et les vieilles images sont des userlands
**i386**. Le `linux-6.12.95` installé (chantier `marionnet-kernel-rootfs`) est **x86_64**
et UML n'a pas d'émulation 32 bits invitée → il faut une **variante i386** du noyau moderne.

### Solution démontrée (preuve du 2026-07-17)

Un `linux-6.12.95` compilé `ARCH=um SUBARCH=i386` (defconfig + `EXT2/EXT3/EXT4_FS`,
`HOSTFS`, `BLK_DEV_UBD`, `UML_NET{,_TUNTAP,_DAEMON}` ; gcc 13 multilib) **boote les deux
images installées jusqu'à `login:`** sur l'hôte 6.8 :

- wheezy-08367 : `VFS: Mounted root (ext4)` → `INIT: version 2.88` → runlevel 2 → `factotum login:` ;
- guignol-18474 (buildroot) : boot complet → `buildroot login:`.

## Plan d'épisodes (prévisionnel)

1. **Build reproductible + install** : variante i386 dans `uml/pupisto.kernel/`
   (config gelée `CONFIG-…-i386` sur le modèle de `CONFIG-modern-base`), epithet distinct
   **`linux-6.12.95-i386`** dans `kernels/` (deux archis de la même version doivent coexister).
2. **Couplage Marionnet** : étendre `SUPPORTED_KERNELS` des `.conf` wheezy/guignol
   (aujourd'hui `/3.2.[6-9]/`) avec le nouvel epithet + paramètres console adéquats ;
   vérifier l'applicabilité des `BOOT_QUIRKS` OCaml (table par noyau ≥ 5) ; test GUI.
3. **Ghostification** : pas de patch ghost sur 6.12 → le vieux relay embarqué appellera
   `ethghost` en vain. Piste privilégiée : hook **`.relay`** via hostfs (supporté par les
   images post-juillet-2013, donc wheezy 2014 ; à vérifier pour guignol 2017) pour une
   ghostification **netns** façon trixie **sans modifier les images**
   (cf. `machine-template.relay` installé et l'archi netns de `marionnet-kernel-rootfs`).
4. **Mandriva** : cas distinct — l'image `machine-mandriva20100215` n'est pas installée
   (seul le `.conf`, qui exige un `[2.6.18-ghost]` absent lui aussi) : restaurer l'image,
   puis décider (même voie i386 moderne, ou abandon documenté).

**Hors périmètre** : ressusciter la série 3.2 (recompilation/backport du stub) ; le
lancement des couples *modernes* (trixie), couvert par `marionnet-kernel-rootfs`.

## Journal d'avancement

- **2026-07-17 — épisode 0 (étude)** : diagnostic de cause (stub SKAS0 des vieux UML
  incompatible hôte 6.8, aucune parade lanceur), preuve de la solution : UML 6.12.95
  `SUBARCH=i386` boote wheezy et guignol jusqu'à `login:` (build ~2 min, boots ~1 min,
  COW jetables). Officialisation du chantier (doc + fiche mémoire + pointeur CLAUDE.md).
- **2026-07-17 — épisode 1 (build reproductible + install)** : option `-i/--i386` dans
  `uml/pupisto.kernel/pupisto.kernel.sh` — pour un noyau ≥ 5.x : config gelée
  `uml/kernel/CONFIG-<ver>-i386` rejouée par `olddefconfig` si présente, sinon seed
  `defconfig ARCH=um SUBARCH=i386` + EXT2/3/4, HOSTFS, UBD, `UML_NET{,_TUNTAP,_DAEMON}` ;
  artefacts et répertoire `_build.*` suffixés `-i386` (la filière legacy < 5.x, déjà i386,
  ignore l'option). Cibles `make <ver>-i386`, `make install`/`install-dry-run` + installeur
  noyau seul `Makefile.d/install.last-built-kernel.sh` (pendant kernel-only de celui de
  `pupisto.debian`). Config gelée `CONFIG-6.12.95-i386` versionnée (gcc 13.3). Preuves :
  build 43 s ; rejeu de la config gelée → `.config` strictement identique ; wheezy
  (`factotum login:`) et guignol (`buildroot login:`) bootent sur COW jetables ; installé
  `/usr/local/share/marionnet/kernels/linux-6.12.95-i386{,.config}` aux côtés du x86_64.
  (Pas encore visible dans la GUI : aucun `.conf` ne matche cet epithet avant l'épisode 2.)
- **2026-07-17 — épisode 2 (couplage GUI)** : les vieux couples sont sélectionnables et
  bootent depuis la GUI.
  - **`.conf` installés** (non versionnés — ils voyagent avec les images ; patch à rejouer
    si une image est retéléchargée, et à reporter un jour côté serveur de téléchargement) :
    dans `/usr/local/share/marionnet/filesystems/`,
    `machine-debian-wheezy-08367.conf`, `machine-guignol-18474.conf` et
    `router-guignol-18474.conf` passent de `SUPPORTED_KERNELS='/3.2.[6-9]/'` à
    `SUPPORTED_KERNELS='/3.2.[6-9]/ /-i386$/'` (regexp **famille**, même esprit que
    `/3.2.[6-9]/` : tout UML moderne i386 conviendra sans réédition) ; le statement est
    **sans PARAMS console** : le repli OCaml « new pairs » (`bin/simulation_level.ml`,
    `ssl=pts con=none con0..N-1=xterm` piloté par `console_no`) est le bon — un PARAMS
    statique ne peut pas exprimer `conN=` dynamique. Sauvegardes pré-patch conservées dans
    `/usr/local/share/marionnet/backups.retro-compat-ep2/` (PAS dans `filesystems/` : tout
    fichier `machine-*`/`router-*` y devient un epithet de la GUI).
  - **Effet de bord corrigé** : le match `SUPPORTED_KERNELS` est une recherche de
    sous-chaîne non ancrée (`StrExtra.First.matchingp`), donc le `/6.12.95/` de trixie
    matchait aussi `6.12.95-i386` (couple amd64/i386 non bootable proposé par la GUI) →
    `machine-debian-trixie-47362.conf` ancré en `/6.12.95$/`, et les **générateurs**
    écrivent désormais `/VERSION\(-ghost\)?$/` (`uml/pupisto.common/toolkit_image.sh`,
    `uml/pupisto.buildroot/pupisto.buildroot.sh`) — accepte toujours « ghost ou pas »,
    exclut les autres variantes.
  - **Bug connexe corrigé (OCaml)** : les compagnons `linux-*.config` de `kernels/`
    apparaissaient comme choix de noyau (le filtre n'excluait que `.conf`/`.relay`) →
    `Filter.exclude_companion_files` dans `bin/disk.ml` exclut aussi `[.]config[~]?$`.
  - **BOOT_QUIRKS vérifié, aucun changement OCaml** : wheezy/guignol sans `INIT_SYSTEM`
    → `sysv` ; la table (OCaml `bin/simulation_level.ml` et bash `pupisto.tester`) n'a
    d'entrée que pour `6.12:systemd` → aucun argument parasite (recap du testeur :
    `boot quirks : 6.12:sysv -> <none>`).
  - **Preuves** : regexps validées par table de vérité `Str` (`-i386$` matche
    `6.12.95-i386` mais ni `6.12.95` ni `…-i386.config` ; `/6.12.95$/` exclut l'i386 ;
    `\(-ghost\)?$` préserve la filière legacy `3.2.64-ghost`). Logs Marionnet (run GUI de
    Jean, `/tmp/34`) : `Selected kernels for "debian-wheezy-08367" / "guignol-18474"
    (machine et router) : [3.2.64-ghost 6.12.95-i386]`, trixie : `[6.12.95]` seul, plus
    aucun epithet `*.config`. Boots GUI complets (tests de Jean) : wheezy +
    `6.12.95-i386` → login `root`, `uname` → `Linux m1 6.12.95 i686` (`/tmp/35`), puis
    guignol OK ; boot headless `pupisto.tester` jusqu'à `login:` pour wheezy (guignol
    headless reste bloqué après « Initialized stdio console driver » sous le canal
    `con0=fd:0,fd:1` du testeur — caprice du testeur, pas du couple : la GUI le boote).
  - **Résiduel (→ épisode 3)** : X11 invité→hôte ne s'affiche pas (`xeyes` gelé,
    `DISPLAY=172.23.0.254:0.0`, eth42 montée non ghostifiée) — attendu : pas de patch
    ghost sur 6.12 et vieux relay embarqué ; c'est le périmètre de la ghostification/relais
    netns par hook `.relay` (épisode 3).
- **2026-07-17 — épisode 3 (X11 invité→hôte + ghostification netns pour wheezy)** :
  - **Cause racine du gel `xeyes` — PAS le noyau i386 ni le relay** : un `port-helper`
    (uml-utilities) **orphelin** d'un run Marionnet mort squattait `0.0.0.0:6000` +
    `[::]:6000` sur l'hôte. Il avait **hérité des sockets d'écoute X11 de
    `marionnet.native`** (le pont `bin/x.ml`, cas 5 : `Network.Socat.dual_inet_of_stream_server`)
    au `fork`/`exec` d'un xterm de console UML — fd non `CLOEXEC` — et leur backlog
    contenait 3 connexions jamais `accept()`ées : les `xeyes` gelés de l'ép. 2 (handshake
    TCP réussi, requête X jamais servie). Tué → port libéré.
  - **Correctif durable (OCaml, ocamlbricks vendored)** : `Unix.set_close_on_exec` sur le
    **socket d'écoute** dans `Network.server` (`lib/STRUCTURES/network.ml`) — l'idiome
    existait déjà pour les sockets de service (forks de connexion) mais pas pour le
    listener. Couvre tous les serveurs ocamlbricks (X11 6000, pts). À reporter dans le
    projet amont ocamlbricks. `dune build` + `make install-for-testing` OK.
  - **Diagnostic headless instrumenté** (réutilisable) : boot wheezy + `6.12.95-i386` sans
    GUI (tap à la main + `timeout`, modèle `pupisto.tester -X`) avec un fichier de
    diagnostic déposé dans le hostfs et **sourcé par le hook du relay embarqué 2014** —
    preuve du hook et diagnostic en un boot. Verdict : ping et **TCP 6000 OK** à travers
    la tap (noyau i386 innocenté), `ip netns` de wheezy (iproute2-ss120521)
    add/move/exec **OK**, socat présent.
  - **Hook `bin/filesystems/machine-debian-wheezy-08367.relay`** (versionné, copié dans le
    hostfs par `simulation_level.ml` car trouvé à côté de l'image) : ghostification netns
    façon archi C trixie adaptée au userland 2012 — forme longue `ip netns exec` (pas de
    `ip -n`), `setsid` (pas de systemd-run) ; socat `X0 → TCP:${host_display_ip}:6000`
    dans le netns ; réécriture `DISPLAY=:0` + xauth (le relay 2014 avait posé
    `172.23.0.254:0.0`) ; en cas d'échec, statu quo (eth42 visible, DISPLAY TCP direct —
    dégradé mais fonctionnel). **Preuve headless bout-en-bout** : eth42 absente du root ns,
    active dans `marionnet-mgmt`, socat vivant, `DISPLAY=:0` posé, et une connexion au
    socket invité `/tmp/.X11-unix/X0` ressort sur le listener hôte 6000 (`CHAIN-OK`).
  - **Couplage installé** (patchs voyageant avec l'image, à rejouer si retéléchargée,
    comme à l'ép. 2) : `.relay` copié dans `/usr/local/share/marionnet/filesystems/` et
    `GHOSTIFICATION=netns` ajouté à `machine-debian-wheezy-08367.conf` → l'OCaml passe
    `host_display_ip` en boot_parameters et ne lance pas le watcher X11 série
    (`machine.ml`), exactement comme trixie. Inoffensif sous 3.2.64-ghost (wheezy n'a pas
    de marionnet-dummy-xserver).
  - **Guignol : pas de ghostification (décision)** : le hook est présent dans le
    `S90marionnet-relay` embarqué 2017 (vérifié par `debugfs`, machine et router) donc le
    mécanisme reste disponible, mais `X11_SUPPORT=none` (rien à réparer), l'`ip` busybox
    n'a pas `netns`, et le **router** a besoin d'eth42 en root ns (telnet quagga
    hôte→invité). eth42 reste donc visible dans guignol, comme aujourd'hui.
  - **Preuve GUI finale** (run de Jean, install testing) : machine wheezy +
    `6.12.95-i386` — `xeyes` affiché sur l'hôte, `ip a`/`ifconfig` sans eth42 dans
    l'invité, arrêt propre ; log `relay script found for "debian-wheezy-08367"`
    (le maillon « détection + copie du hook par l'OCaml » validé en situation).
- **2026-07-17 — épisode 4 (abandon des autres distros + remap automatique au chargement
  d'un vieux `.mar`)** :
  - **Décision de périmètre : seuls wheezy et guignol sont rétro-supportés.** Mandriva,
    pinocchio et lenny sont **abandonnés** : leurs `.conf` orphelins (sans image) restent
    versionnés dans `bin/filesystems/` **pour l'historique** (décision : pas de `git rm`),
    et sont inertes (un `.conf` sans image ne crée pas d'epithet GUI). L'ancienne piste
    « restaurer l'image mandriva » (plan initial, point 4) est close.
  - **Remap automatique à la désérialisation** (« Projet → Ouvrir ») : les vieux `.mar`
    référencent des kernels `2.6.18-ghost`/`3.2.64-ghost` (stub SKAS0 cassé par les hôtes
    modernes) et parfois des filesystems non installés. Nouvelles méthodes
    `remap_{absent_distrib,absent_variant,obsolete_kernel}_at_import` dans
    `user_level.ml` (`virtual_machine_with_history_and_ifconfig`), câblées dans
    `eval_forest_attribute` de `machine.ml` et `router.ml` (ordre garanti distrib →
    variant → kernel, celui de `to_tree`) :
    - **kernel** : si la série est vieille (major < 4) **et** l'hôte cassant
      (`Initialization.host_kernel_breaks_old_uml_stubs`, lecture de
      `/proc/sys/kernel/osrelease`, seuil `(5,15)` — **empirique** : prouvé cassé sur 6.8,
      aucun seuil documenté publiquement trouvé, choix conservateur), ou si le kernel
      n'est pas installé → bascule vers un kernel supporté par le filesystem (déjà
      remappé), **préférence `-i386`** (vieilles images = userlands i386) :
      `3.2.64-ghost` → `6.12.95-i386` (wheezy/guignol), `2.6.18-ghost` → `6.12.95`
      (après remap du filesystem vers trixie). Sur un hôte < 5.15, les vieux couples
      installés continuent de tourner tels quels (pas de remap).
    - **filesystem** : build absent de la même famille (`guignol-21852` →
      `guignol-18474`), sinon (distro abandonnée, ex. `mandriva20100215`) **fallback
      cross-distro** vers le filesystem par défaut d'un composant neuf
      (`get_default_epithet`, en pratique trixie) — **uniquement si le projet ne porte
      aucun état COW** pour ce composant (un COW référence son backing exact, MTIME
      compris) ; les rows du treeview history sont réalignées. Avec COW : pas de remap,
      le composant est **écarté du projet chargé** par le mécanisme historique
      `try_to_add_*` (échec de `set_epithet` avalé par `network#eval_forest_child`) —
      le warning émis est la seule trace visible ; il conseille de **ne pas sauvegarder**.
      Effet bonus : les `.mar` v1 à `distrib="default"` (epithet plus installé
      aujourd'hui), qui ne se chargeaient plus du tout, se chargent en trixie.
    - **variant** : une variant disparue avec son filesystem (notamment après remap) est
      abandonnée (`None`) avec warning, au lieu du `failwith` de `check_variant`.
  - **Restitution GUI** : warnings collectés dans `class network`
    (`add_import_warning`/`get_and_reset_import_warnings`), affichés par
    `state#open_project_async` en **dialogue récapitulatif** (`Simple_dialogs.warning`
    « Project adapted at loading ») après l'import — ou joints au dialogue d'erreur
    « Failed loading the project » si l'import lève. Chaînes gettext (`s_`/`f_`) mais
    **catalogues non régénérés** dans cet épisode (fallback anglais ; à ramasser lors
    d'une future passe i18n).
  - **Preuves** (CLI, `marionnet.exe -d FILE.mar`, logs `import remapping:`) : `tp9.mar`
    (guignol-21852→18474 + 5× 3.2.64-ghost→6.12.95-i386) ; `m1m2m3-dhcpd-conf.mar`
    (3 COW wheezy : remap kernel seul) ; `tp6c.mar` (2.6.18 et 3.2.64 remappés, warnings
    simples) ; `tp.mar` (mandriva → trixie, sans COW) ; cas fabriqué « distrib absente +
    COW » (garde refusée, composant écarté, warning honnête). Bruit `Network.Accepting`
    en fin de run = séquence d'arrêt des threads accept (préexistant, bénin).
    Reste : validation visuelle du dialogue en GUI (run interactif).
- **2026-07-17 — épisodes 5-6 (UI/UX du dialogue « Project adapted at loading » + fix du
  comment d'historique périmé)** :
  - **Dialogue dédié, scrollable, à divulgation progressive** (`d5759e6`, `264b18a`,
    `18ba114`). Le récapitulatif réutilisait le `dialog_MESSAGE` générique de glade (un
    unique label sans scroll → bouton CLOSE poussé hors écran dès qu'il y a beaucoup de
    composants, phrases concaténées illisibles). Remplacé par
    `Simple_dialogs.recapitulative`, construit **programmatiquement** (comme
    `ask_text_dialog`, **sans toucher glade/`gui.ml`**) : en-tête fixe (icône + titre court
    gras + préambule), **`GBin.scrolled_window` à hauteur plafonnée (320 px)** contenant
    **un `GBin.expander` par point** (résumé visible, détail au clic), **action area fixe
    hors du scroll** (CLOSE toujours atteignable). Marqueur ⚠ sur les points `Warning`.
  - **Warnings d'import structurés** : `type import_warning = { iw_summary; iw_detail;
    iw_severity : [ `Info | `Warning ] }` (+ `string_of_import_warning` pour le chemin
    d'erreur et les logs) remplace la `string` plate ; les 5 messages de
    `remap_*_at_import` sont scindés résumé court / détail (pourquoi + conséquences),
    sévérité `Info (bascule inoffensive) vs `Warning (perte : composant écarté sous COW,
    kernel sans remplacement). `user_level.mli` synchronisé.
  - **Titre court + préambule** : `recapitulative` prend `~header` (gras, court, « N
    automatic adjustment(s) were applied ») et `?preamble` (phrase d'introduction, avec un
    `\n` dur avant « Click an item… » pour ne pas élargir la fenêtre).
  - **Piège lablgtk3** : `GBin.expander` de ce binding **n'a pas** `~use_markup` — label
    d'expander en texte brut (résumé passé verbatim, ⚠ en UTF-8 littéral).
  - **Fix comment d'historique périmé** (`5c77aed`) : après un remap de distribution,
    `redirect_history_rows_to_distrib` ne mettait à jour que le champ caché **Prefixed
    filesystem**, laissant la colonne **Comment** de l'onglet Disques figée sur son libellé
    auto-généré pré-remap (« machine-default »). **Bénin** (le Comment est cosmétique,
    jamais lu pour reconstruire le filesystem — seul `prefixed_filesystem` l'est) mais
    trompeur et resauvegardé. Nouvelle méthode
    `Treeview_history.t#redirect_device_to_prefixed_filesystem` (là où vit la convention
    `comment = prefixed_filesystem ^ suffixe-variant`) : met à jour le champ fonctionnel et
    ne rafraîchit le Comment **que** s'il porte encore le libellé auto-généré (préserve une
    annotation utilisateur ou « [no comment] », via `String.starts_with`).
  - Preuve : `dune build` rc=0 ; dialogue validé en GUI par Jean. Colonne Comment à
    reconfirmer visuellement (champ GUI non journalisé).
- **2026-07-17 — épisode 7 (remap de distribution intelligent : histoire des images + RAM)** :
  le fallback cross-distro de `remap_absent_distrib_at_import` (déclenché quand aucun build
  same-family n'est installé — `default`, mandriva, lenny, pinocchio) ne renvoyait que
  `get_default_epithet` (trixie). Nouveau `choose_cross_distro_target ?memory` (helpers
  `epithet_contains`, `find_installed_filesystem_containing`) reflétant les deux catégories
  historiques d'images — X11/wireshark (wheezy, trixie) vs terminal texte (guignol) :
  - `{mandriva, lenny} → wheezy` (sinon trixie) ;
  - `{pinocchio, router-default} → guignol` (sinon wheezy, sinon trixie) ;
  - `machine-default` : RAM (`self#get_memory`) < 96 → wheezy (sinon trixie), ≥ 96 → trixie.
  Pivot **96** = `MEMORY_SUGGESTED_SIZE` de wheezy (barème installé : guignol 24, pinocchio 32,
  mandriva/lenny 48, wheezy 96, trixie 128). La RAM est disponible au remap car `"memory"`
  précède `"distrib"` dans `machine.to_tree` (`set_memory` s'exécute avant), passée en `?memory`
  depuis `machine.ml` ; les routers n'en ont pas besoin (`router-default → guignol` via le
  préfixe `vm_installations#prefix`). `.mli` (user_level, machine) synchronisés. Same-family
  (guignol-21852→18474, wheezy→wheezy) et garde COW **inchangés**.
  - Preuves CLI (`marionnet.exe -d`, build rc=0) : `tp6c` + `projet-marionnet*` (machine-default
    48 M → **wheezy**, avant trixie) ; `tp.mar` (mandriva → **wheezy**) ; `tp9` (guignol-21852 →
    guignol-18474 same-family). Branches `router-default→guignol`, `RAM≥96→trixie`,
    `pinocchio→guignol`, `lenny→wheezy` : logique en place, **non exercées** faute de `.mar`
    d'exemple les portant.
