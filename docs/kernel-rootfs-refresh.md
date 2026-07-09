# Chantier « rafraîchissement noyaux + rootfs » (`marionnet-kernel-rootfs`)

Rafraîchir le noyau UML vers **6.12.x** (dernier LTS) et le rootfs vers **Debian 13 (Trixie)**,
à partir de la livraison Dave Appadoo, en ré-exprimant son travail dans la machinerie `pupisto.*`
de Marionnet. **Ghostification différée** (noyau vanilla, comme Dave). **Bloque** le chantier
vwifi (`docs/vwifi-integration.md`).

Source d'analyse : `docs/analyse-dave-appadoo-20260708.md`. Décisions actées (2026-07-08) :
ré-exprimer dans `pupisto.*` ; rootfs standard léger séparé du rootfs vwifi ; init systemd natif
pour le nouveau rootfs.

## Périmètre

- **Rootfs standard** : rafraîchir Debian 13 via `uml/pupisto.debian/pupisto.debian.sh`, léger
  (pas la pile GUI qt6/weston/gimp de Dave, spécifique vwifi). Chantier majeur : passage SysV →
  **systemd** (Trixie n'a plus `/etc/inittab`, `update-rc.d` pour les services, etc.).
- **Noyau** : compilation UML Linux 6.12 (`ARCH=um`, amd64) dans `uml/pupisto.kernel/pupisto.kernel.sh`,
  `make defconfig` frais non interactif, patch ghost rendu optionnel.
- **Dispatch de boot OCaml (scope élargi)** : passer le nouveau rootfs à systemd change la
  coordination hôte↔invité du démarrage. Marionnet doit lancer à la fois les **anciennes** VM
  (SysV, vieux noyaux) et les **nouvelles** (systemd). → marqueur `INIT_SYSTEM=` dans le `.conf`
  du filesystem (écrit par pupisto), lu par `bin/disk.ml` (défaut `sysv` si absent → zéro
  régression), dispatché dans `bin/simulation_level.ml` (args noyau ~879-934 + déclenchement du
  relay). Ce volet fait sortir le chantier de `uml/` seul.

Hors périmètre : vwifi côté OCaml, rootfs vwifi (→ chantier vwifi).

## Décisions ouvertes (checkpoint)

1. **Design du dispatch de boot** : marqueur `.conf` + défaut legacy (en confirmation).
2. Frontière exacte entre rootfs standard (ici) et rootfs vwifi (chantier vwifi).
3. Approche systemd fine (unité native vs génération) pour le relay et les services.

## Journal d'avancement

- **2026-07-08** — épisode 0 : officialisation + analyse. Cibles fixées (Trixie / 6.12 /
  ghost différée / systemd natif). Lecture de `pupisto.debian.sh` et `pupisto.kernel.sh`.
  Découverte que le passage systemd impose un **dispatch de boot OCaml** (compat SysV/systemd) —
  scope élargi hors `uml/`. Aucun code touché.
- **2026-07-08** — épisode 1 (`58e4313`, `pupisto.debian.sh`) : plumbing Trixie
  (DEFAULT_RELEASE, garde release, security suite `-security`, nettoyage MANDATORY_PACKAGES).
  Reste : `package_catalog.trixie.selection`.
- **2026-07-08** — épisode 2 (`pupisto.kernel.sh`, `uml/kernel/`) : **noyau UML 6.12.95 compile**.
  Approche centrée sur le travail de Dave : sa `.config` (6.5.13, amd64, modulaire, systemd-ready)
  versionnée en `uml/kernel/CONFIG-modern-base`, migrée vers 6.12 par `make olddefconfig ARCH=um`
  via une nouvelle fonction `create_modern_kernel_config` (pas de fusion 2.6.18, pas de `=m→=y` :
  modularité préservée, dont `mac80211_hwsim=m` pour vwifi). Corrigés en passant : `KERNEL_SUBDIR`
  généralisé (`v6.x`), build amd64 parallèle (`make ARCH=um -j`, plus de `SUBARCH=i386`), et un
  **bug préexistant** exposé par le renommage du dépôt — `get_our_marionnet_slash_uml_directory_path`
  cherchait le littéral `/marionnet/uml/` dans `$PWD` (→ `/kernel`), désormais dérivé de
  `${BASH_SOURCE[0]}`. Config compilant figé en `uml/kernel/CONFIG-6.12.95`. `.gitignore` :
  globs `_build.*/` + `linux-*/`. **Boot NON encore validé** (test hôte, côté Jean).
- **2026-07-08** — épisode 3 (`pupisto.debian.sh`, `toolkit_image.sh`, `machine-template.conf`,
  `pupisto.debian/Makefile`) : câblage 6.12 + **socle systemd**. Cible make `trixie` (amd64/ext4/6.12.95,
  + `trixie-no-kernel`/`-custom`/`-edit`, `help`). `DEFAULT_KERNEL_VERSION` → 6.12.95 (make_or_link_the_kernel lie
  `_build.linux-6.12.95*`). Marqueur `INIT_SYSTEM` (`sysv`/`systemd`) : champ du template `.conf`,
  écrit par `toolkit_image.sh`, dérivé de la release (`case` : wheezy→sysv, sinon systemd) —
  côté Marionnet, défaut `sysv` si absent (rétro-compat). `marionnet-relay` : **unité systemd
  native** (`.service` oneshot `After=network.target`, wants-symlink offline) vs `update-rc.d`
  (dispatch sur `INIT_SYSTEM`). Fonctions SysV rendues conditionnelles sous systemd :
  `fix_etc_inittab` (getty géré par systemd via `console=`), `fix_reboot` (workaround 3.2.x
  obsolète, casserait `systemctl`), `prevent_non_vital_services` (SysV `update-rc.d` — refonte
  `systemctl disable` **TODO**). Vérif : `bash -n` OK + substitution marqueur testée. **Build/boot
  NON testés** (debootstrap/sudo/réseau → côté Jean). RESTE : ethghost/ghostification ;
  `package_catalog.trixie` (voir épisode 5).
- **2026-07-08** — épisode 4 (`disk.ml`, `user_level.ml`, `simulation_level.ml`, `machine.ml`,
  `router.ml` ; NON committé) : **volet OCaml du dispatch de boot**. `disk.ml` lit `INIT_SYSTEM`
  du `.conf` (méthode `init_system_of`, défaut `"sysv"` si absent — rétro-compat). Threading
  bout-en-bout `user_level.get_init_system` → `machine.ml`/`router.ml` → `machine_or_router`
  (+ `_with_accessory_processes`) → `uml_process`. Dans `uml_process`, si `init_system="systemd"`
  et qu'aucun `console=` explicite n'est déjà présent, ajout de `console=tty0` aux arguments
  noyau (déduction du comportement documenté de `systemd-getty-generator`, **hypothèse non
  confirmée par un boot réel** — SysV n'a pas besoin de ce paramètre car `/etc/inittab` démarre
  déjà un getty explicite sur tty0). **Non compilé** : la toolchain OCaml 4.13.1 gelée
  (camlp4) n'est plus disponible sur la machine de dev (cf. mémoire
  `marionnet-build-toolchain-cassee`, chantier séparé) — vérification faite par relecture/grep
  du threading uniquement. À recompiler et tester au boot dès la toolchain restaurée.
- **2026-07-09** — épisode 5 (`pupisto.debian.sh.files/package_catalog/{Makefile,
  make_package_catalog_from_binary_list.sh}`, `.gitignore`) : **outillage
  `package_catalog.trixie` généralisé**, reliquat de l'épisode 1. Le Makefile dupliquait un
  bloc de règles par release (`wheezy`, `squeeze`) ; remplacé par des règles génériques
  (`package_catalog.%.GENERATED`, `.COMPLETE.COMMENTED`, `.COMPLETE.COMMENTED.selection`) +
  `RELEASES=wheezy squeeze trixie`. `make_package_catalog_from_binary_list.sh` accepte
  désormais `trixie` (`ARCH=amd64`, cohérent avec `DEFAULT_ARCH` de `pupisto.debian.sh`,
  vs `i386` legacy pour wheezy/squeeze). Deux pièges GNU Make rencontrés et corrigés en
  cours de route : (1) une pattern-rule sans recette est silencieusement ignorée
  (contrairement à une règle explicite) — ajouté une recette de garde (`test -f`) ; (2)
  les pattern-rules traitent les fichiers nouvellement créés en chaîne comme des
  intermédiaires jetables et les `rm` en fin de build — `.PRECIOUS` ajouté pour préserver
  `GENERATED`/`COMPLETE.COMMENTED` (coûteux : `GENERATED` = un vrai `debootstrap`+`apt-file
  update` en chroot, ~1h, sudo+réseau). Vérifié en profondeur par `make -n` sur toutes les
  cibles (wheezy/squeeze/trixie) et comparaison bit-à-bit avec le Makefile d'origine (non-
  régression confirmée). **`package_catalog.trixie.selection` n'existe TOUJOURS PAS** : son
  contenu ne peut être produit qu'en lançant réellement `make trixie` (sudo/réseau, ~1h) →
  côté Jean, pas fabriqué de mémoire (risque d'halluciner des noms de paquets Debian trixie
  inexistants). `trixie-edit` du Makefile racine restera cassé jusque-là (même état
  préexistant que `stretch-edit`, jamais eu de catalogue stretch non plus). En passant :
  `.gitignore` élargi à `uml/pupisto.debian/_build.*/` (symétrie avec `pupisto.kernel`) — un
  `_build.debian-trixie-…23h54/` (debootstrap `make trixie` interrompu) traînait en non-suivi.
