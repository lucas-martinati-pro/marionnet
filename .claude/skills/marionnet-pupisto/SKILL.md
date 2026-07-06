---
name: marionnet-pupisto
description: Chantier systèmes invités de Marionnet (uml/) — construire noyaux UML patchés (ghostification) et filesystems invités (pupisto.debian par debootstrap, pupisto.buildroot), outillage guest. Charger pour toute intervention sous uml/ ou sur la fabrication des images/noyaux invités.
---

# Systèmes invités (pupisto)

## Orientation

- Filesystem Debian : `uml/pupisto.debian.sh` (debootstrap ; catalogues de paquets par
  release dans `pupisto.debian/package_catalog/`).
- Filesystem Buildroot : `uml/pupisto.buildroot.sh` (overlays quagga, dhcpd, radvd,
  ethghost.mk dans `pupisto.buildroot/`).
- Noyau UML : `uml/pupisto.kernel.sh` (téléchargement + patches de ghostification de
  `uml/kernel/` + compilation ; `_build.downloads/` et sources sont git-ignorés).
- Fichiers embarqués dans l'invité : `uml/guest/` (`marionnet-relay` = init de communication
  invité↔hôte ; faux serveur X ; clé ssh de labo).
- Fonctions partagées : `uml/pupisto.common/toolkit_*.sh` (images, chroot, config, debug) —
  bibliothèques **sourcées**, sans `set -e` (contrainte de sourçage), ne pas les « durcir ».

## Règles bash locales

- Respecte le motif des orchestrateurs : `set -e`, fonctions nommées, **auto-journalisation**
  (ré-exécution de soi-même sous `tee` avec log mktemp + récupération du code de sortie) —
  préserve ce mécanisme dans toute modification de `pupisto.*.sh`.
- Les scripts destinés à l'invité tournent sous **busybox sh** : pas de bashismes, pas de
  `set -u`/`pipefail` là-dedans. Couplage debug : `MARIONNET_DEBUG=true` → `set -x`
  (cf. `marionnet-relay`).
- Du bash NEUF côté hôte peut être moderne (`set -euo pipefail`) s'il n'est ni sourcé par
  l'existant ni destiné à l'invité.
- `uml/startup.old/` est un vestige apparent (supersédé par `guest/marionnet-relay`) :
  ne t'en inspire pas sans vérification.

## Ghostification

Les patches de `uml/kernel/` rendent les interfaces de service invisibles de l'invité ;
`uml/ethghost/` (C + Makefile) les pilote depuis l'invité. Doc de référence :
`uml/kernel/doc/README.Ghostification` (+ erreurs connues fr/en). Toute montée de version
noyau = re-porter ces patches (configs `.config` par version dans `uml/kernel/`).

## Vérification

Un filesystem/noyau construit se valide en le déclarant à Marionnet (conf dans
`bin/filesystems/*.conf`, inventaire runtime par `bin/disk.ml`) et en démarrant une machine
dans la GUI — pas seulement en obtenant l'image sans erreur.

Référence : `docs/ARCHITECTURE.md` § 8 ; rôles : `uml/CLAUDE.md`.
