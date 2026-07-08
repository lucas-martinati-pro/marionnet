# Chantier « intégration vwifi » (`marionnet-vwifi`)

Intégrer **vwifi** (wifi simulé via `mac80211_hwsim`, `github.com/Raizo62/vwifi`) dans
Marionnet. Touche l'OCaml (`bin/`) et le runtime `uml/`. **BLOQUÉ** par le chantier
`marionnet-kernel-rootfs` (vwifi exige un noyau 6.1 avec support wireless + un rootfs le
portant). Source d'analyse : `docs/analyse-dave-appadoo-20260708.md`.

## État de départ (livraison Dave)

Preuve de concept **système**, pas une feature Marionnet : 3 machines câblées sur un switch,
vwifi lancé manuellement à l'intérieur (un serveur = médium radio, des clients connectés en
TCP/IP, interfaces `wlanN` via `mac80211_hwsim`). Aucun code OCaml. Le wifi n'apparaît pas
dans la topologie Marionnet.

## Décision de périmètre à trancher (au déblocage)

- **(a) Minimal** — livrer le rootfs/kernel vwifi + scripts, lancement manuel dans les guests
  (≈ Dave, mais packagé proprement dans Marionnet).
- **(b) Natif** — modéliser un médium sans-fil de première classe dans le modèle à deux niveaux
  (`user_level`/`simulation_level`), interfaces wlan sur les machines, dialogue GTK
  (SSID / WPA / ouvert). Gros travail OCaml via le patron composant (skill `marionnet-composants`).

## Journal d'avancement

- **2026-07-08** — épisode 0 : chantier officialisé, **bloqué** sur le kernel. Analyse de la
  livraison Dave archivée. Aucun code touché.
