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
