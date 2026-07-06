# uml/ — construction des systèmes invités

Tout ce qui fabrique ce que Marionnet exécute dans ses machines virtuelles UML :
noyaux patchés, filesystems invités, outillage embarqué. Shell (bash) + patches + un outil C.
Chantier : charger le skill `marionnet-pupisto`.

## Rôle des sous-dossiers

- `README` — répartition historique : patches noyau (Roudière/Saiu) vs scripts pupisto (Loddo/Seignard).
- `kernel/` — patches de « **ghostification** » (interfaces réseau fantômes invisibles de
  l'invité) + configs `.config` pour noyaux UML 2.6.x→3.x ; doc dans `kernel/doc/` ;
  `older-versions/` archivées.
- `ethghost/` — outil C userland (+ Makefile) pilotant la ghostification dans l'invité.
- `guest/` — fichiers installés dans l'invité : `marionnet-relay` (init de communication
  invité↔hôte), faux serveur X, clé ssh, `make-tarball-for-guest-system.sh`.
- `pupisto.common/` — bibliothèques **sourcées** : `toolkit_image.sh` (images disque),
  `toolkit_chroot.sh`, `toolkit_config_files.sh`, `toolkit_debugging.sh`.
- `pupisto.debian/` + `pupisto.debian.sh` — filesystem Debian par debootstrap
  (catalogues de paquets par release).
- `pupisto.buildroot/` + `pupisto.buildroot.sh` — idem via Buildroot (overlays quagga,
  dhcpd, radvd, ethghost.mk…).
- `pupisto.kernel/` + `pupisto.kernel.sh` — téléchargement + patch + compilation des noyaux
  UML (`_build.downloads/` et sources git-ignorés).
- `startup.old/` — `?` anciens scripts de démarrage invité, vraisemblablement supersédés par
  `guest/marionnet-relay` (vestige apparent, non confirmé).

## Conventions bash locales

- Orchestrateurs `pupisto.*.sh` : `set -e` + fonctions nommées + **auto-journalisation**
  (le script se ré-exécute sous `tee` avec log mktemp) — motif à préserver.
- Pas de `set -u`/`pipefail` dans l'existant ; les toolkits sourcés et les scripts destinés
  à l'invité (busybox sh) n'ont pas de `set -e` (contrainte de sourçage/busybox).
  Du bash **neuf** côté hôte peut être moderne ; ne pas « durcir » l'existant en passant.
- `marionnet-relay` active `set -x` si `MARIONNET_DEBUG=true` (couplé au mode debug hôte).

*Index généré depuis l'audit du 2026-07-06.*
