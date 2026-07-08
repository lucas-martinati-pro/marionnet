# Chantier « rafraîchissement noyaux + rootfs » (`marionnet-kernel-rootfs`)

Rafraîchir les noyaux UML vers la série **6.1** et le rootfs **Debian 12 (Bookworm)**, à
partir de la livraison Dave Appadoo, en ré-exprimant son travail dans la machinerie `pupisto.*`
de Marionnet. Touche `uml/`. **Bloque** le chantier vwifi (`docs/vwifi-integration.md`).

Source d'analyse : `docs/analyse-dave-appadoo-20260708.md`.

## Périmètre

- **Noyau** : compilation UML Linux 6.1.x (`ARCH=um`) intégrée à `pupisto.kernel.sh`, à partir
  du `.config` fourni par Dave, rendu non interactif (`olddefconfig`, pas `xconfig`). Doit
  activer `mac80211_hwsim`/`cfg80211`/`mac80211` (jonction avec le chantier vwifi). Reporter les
  patches de ghostification de `uml/kernel/` sur la 6.1.
- **Rootfs standard** : rafraîchir le rootfs Debian 12 via `pupisto.debian.sh`, en le gardant
  **léger** (ne pas reprendre la pile GUI qt6/weston/gimp/wireshark de Dave, spécifique vwifi).

Hors périmètre : vwifi côté OCaml, rootfs vwifi (→ chantier vwifi).

## Décisions ouvertes (checkpoint)

1. Ré-exprimer dans `pupisto.*` (recommandé) vs adopter le script `CHROOT_rootfs_kernel.sh` tel quel.
2. Frontière exacte entre rootfs standard (ici) et rootfs vwifi (chantier vwifi).

## Journal d'avancement

- **2026-07-08** — épisode 0 : chantier officialisé (fiche `marionnet-kernel-rootfs`, cette doc,
  pointeur CLAUDE.md). Analyse de la livraison Dave archivée. Aucun code touché.
