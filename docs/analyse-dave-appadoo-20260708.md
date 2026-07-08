# Analyse de la livraison Dave Appadoo (2026-07-08)

Source : `../marionnet.new-kernel-rootfs-and-vwifi.Dave-Appadoo` (dépôt git séparé
`github.com/daveappadoo/vwifi_uml`, 28 commits, sprints étudiants févr. 2024 → janv. 2025,
248 K). Rapport de lecture destiné à alimenter deux chantiers d'intégration **distincts et
séquencés** (le kernel bloque vwifi). Immuable — les leçons sont distillées dans les fiches
chantier et les docs dédiées.

## Ce que Dave a livré (constat)

Aucune ligne d'OCaml, aucun patch. La livraison est **système/scripts** :

- `createUML_KERNEL/CHROOT_rootfs_kernel.sh` (209 l.) — un script unique qui, via
  **debootstrap + chroot** (Debian 12 Bookworm, amd64), construit un rootfs, y compile
  **vwifi** (`Raizo62/vwifi`, `make && make install` dans le chroot), puis télécharge et
  compile un **noyau Linux 6.1.1 en `ARCH=um`** et installe ses modules dans l'image. Le
  script se réclame lui-même de `pupisto.debian.sh` (commentaire ligne 114).
- Scripts vwifi runtime (`vwifi_server.sh`, `vwifi_client*.sh`) déposés dans `/vwifi` de
  l'invité ; `marionnet-relay.sh` (541 l., variante du relay invité de Marionnet).
- `.old/` — première approche **Docker** (abandonnée au profit de debootstrap/chroot).
- `vwifiMarionnet.mar` — démo : 3 machines (`server`, `client1`, `client2`) + 1 switch `S1`
  + câbles, machines déclarées avec `distrib=vwifi-913`, `kernel=vwifi-905` (epithets ad hoc).
- Docs (`README.md`, `documentation.md`, `vwifiServer_Client_commands.md`).

## Modèle vwifi (important pour le volet OCaml)

vwifi (`Raizo62/vwifi`) simule le wifi via le module noyau `mac80211_hwsim`. Architecture :
un **serveur** = le *médium radio*, des **clients** = stations/AP, tous reliés par un réseau
**TCP/IP classique** (ici eth0 en 192.168.100.0/24 à travers le switch Marionnet). Les clients
enregistrent des interfaces `wlanN` (`vwifi-add-interfaces`), se connectent au serveur par IP,
puis se comportent en wifi réel (hostapd pour un AP, wpa_supplicant/`iw connect` pour une
station, mode moniteur + tcpdump pour la capture).

**Conséquence de conception :** dans la démo, le wifi n'existe PAS dans la topologie Marionnet
— ce sont 3 machines *câblées* sur un switch, qui lancent vwifi *à la main* en interne. Le
serveur vwifi (le médium) est juste un processus dans une des machines. Rendre vwifi « natif »
dans Marionnet (médium sans-fil comme entité de première classe, interfaces wlan, GUI
SSID/WPA) est un travail de conception OCaml à part entière — c'est l'enjeu du chantier vwifi,
pas quelque chose que Dave a déjà fait.

## Volet 1 — noyau + rootfs (touche `uml/`) — chantier `marionnet-kernel-rootfs`

Cible : noyaux UML **6.1** + rootfs Debian 12 rafraîchi. Points à traiter en ré-exprimant
le travail de Dave dans ta machinerie `pupisto.*` (approche recommandée : debootstrap/chroot,
déjà celle de Dave — pas Docker) :

- **Séparer** la construction du noyau (→ `pupisto.kernel.sh`) de celle du rootfs
  (→ `pupisto.debian.sh`) ; Dave les fusionne dans un seul script.
- **Séparer** le rootfs *standard* rafraîchi du rootfs *vwifi* : le standard reste léger ;
  Dave a empilé une lourde pile GUI (qt6, weston, wayland, gimp, wireshark…) inadaptée au
  guest UML pédagogique.
- **Reproductibilité** : remplacer `make ARCH=um xconfig` (GUI interactif, ligne 188) par
  `olddefconfig`/`oldconfig` non interactif à partir du `.config` fourni ; épingler le commit
  de `Raizo62/vwifi` ; `set -euo pipefail` ; corriger le no-op `rm -rf $(mktemp -d)` (l. 205)
  et la redondance rc.local + service systemd.
- **Couplage avec vwifi** : le `.config` 6.1 doit activer `mac80211_hwsim`, `cfg80211`,
  `mac80211` (sinon vwifi ne tourne pas) — c'est le point de jonction concret entre les deux
  volets.

## Volet 2 — vwifi (touche l'OCaml + runtime `uml/`) — chantier `marionnet-vwifi`

**Bloqué** tant que le volet 1 n'a pas fourni un noyau 6.1 avec support `mac80211_hwsim` et un
rootfs portant vwifi. Décision de périmètre à trancher au checkpoint du chantier :
- (a) **minimal** : livrer le rootfs/kernel vwifi + scripts, lancement manuel (≈ Dave, packagé) ;
- (b) **natif** : modéliser un médium sans-fil de première classe dans le modèle à deux niveaux
  (`user_level`/`simulation_level`), interfaces wlan sur les machines, dialogue GTK
  (SSID/WPA/ouvert) — gros travail OCaml, s'appuie sur le skill `marionnet-composants`.

## Récapitulatif des décisions ouvertes (checkpoints à venir)

1. Ré-exprimer dans `pupisto.*` (recommandé) vs adopter tel quel le script de Dave.
2. Rootfs standard vs rootfs vwifi : deux artefacts distincts.
3. Périmètre vwifi OCaml : minimal (a) vs natif (b).
