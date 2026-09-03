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
- **2026-07-09** — épisode 6 : **`make trixie` produit une image Debian 13 complète**
  (verrou A levé). Catalogue trixie généré (`.GENERATED` par debootstrap + `apt-file`, avec fixes
  `--include` release-aware : `realpath` retiré — absent de trixie —, `aptitude` ajouté pour
  `aptitude show`), puis `package_catalog.trixie.selection` de **148 paquets** dérivée à la main :
  base = équivalents des anciennes VMs (`binary_list.UNION` ∩ trixie via apt-file), + **couche
  pédagogique 2026** (scapy, sssd/libnss-ldapd/nslcd, nftables, frr, kea, chrony, iperf3, dovecot,
  python3-pip/ipython3, neovim, tmux…). Décisions Jean : **X11 minimal (nested)** + **suite serveur
  complète** (DNS/DHCP/LDAP/mail/web/SNMP/NFS/Samba/routage) + tout garder + `git`. `julia`/`vscode`
  écartés (absents de trixie/main). Validation noms/tailles **sans chroot** via l'index
  `dists/trixie/main/binary-amd64/Packages.xz`. Bugs bloquants trixie corrigés au fil des runs
  réels : `--force-yes` retiré (supprimé d'apt 1.1) ; `ensure_host_dependencies` (auto-install
  debootstrap, script autonome) ; **`apt-get install` dé-`once`-ifié** — le wrapper `once` avalait
  le code d'échec (`"$@" || code=$?` neutralise `set -e`), donc un `-c` sur un build raté sautait
  l'install et produisait une image **incomplète marquée « Success »** (piège corrigé : l'échec
  apt est de nouveau fatal, et `apt-get` étant idempotent le `-c` le rejoue) ; `toolkit_image.sh`
  `local $FS_LOC` (identifiant invalide) + template `share/filesystems` → `bin/filesystems`
  (déplacé par le port dune ; idem `pupisto.buildroot.sh`) ; conflits de sélection `mtr`/`mtr-tiny`
  et `vsftpd`/`inetutils-ftpd`. **Phase 4** (modernisation transverse `uml/`) : `aptitude` →
  `apt-get` dans les 4 cibles `dependencies` (`pupisto.{kernel,debian,buildroot}` + catalogue) ;
  `dependencies` ajouté en prérequis des cibles release du catalogue. Image finale : ext4 ~2,8 Go,
  **1033 paquets** installés, `X11_SUPPORT=xhosted`, `INIT_SYSTEM=systemd`, kernel 6.12.95 lié.
  **Boot NON encore testé** (socle systemd + hypothèse `console=tty0` de l'ép. 4 à valider ; test
  intégral via Marionnet bloqué par la toolchain OCaml, chantier `marionnet-build-toolchain-cassee`).
- **2026-07-09/10** — épisode 7 (`uml/pupisto.tester/pupisto.tester.sh` (nouveau),
  `pupisto.debian.sh`, `package_catalog.trixie.selection`) : **boot-test du socle systemd + durcissement
  du boot par une boucle de diagnostic** (verrou B levé pour le boot UML manuel). Nouveau script
  `pupisto.tester.sh` : boot-test mono-machine dans un COW jetable (image intacte), modes `xterm`
  (interactif) et `--headless` (console sur stdout sous `timeout`, scriptable pour une boucle
  lancements/corrections sans sudo ni X11). Sans argument il retrouve la dernière image, en déduit le
  kernel apparié et reproduit le dispatch de boot de Marionnet via une **table `BOOT_QUIRKS`**
  (pseudo-module `Map` de bashbricks, clé `série:init` → args noyau ; `6.12:systemd → console=tty0`) —
  contrepartie Bash de ce que `simulation_level.ml` portera. Décision Jean : les options UML dépendent
  du **couple (kernel,image)** → table indexée plutôt que des `if` en dur (lève sa contrainte « pas de
  bashbricks dans le tester » pour ce `Map`). La boucle de boot-test (headless, pilotée par Claude) a
  débusqué et corrigé **6 bugs** du socle systemd, tous validés au boot réel : **(#1)** `/etc/fstab`
  swap `nofail` **+ `x-systemd.device-timeout=1`** (release-aware : `nofail` seul insuffisant — le job
  `dev-ubdb.device` gardait son timeout 90 s ; le device UML `/dev/ubdb` peut ne jamais apparaître) ;
  **(#2)** `runit` retiré de la sélection (le `runsvdir` spammait la console — vestige wheezy) ;
  **(#3)** `prevent_non_vital_services_from_starting` **réécrite en whitelist stricte 2-passes** :
  décision pédagogique de Jean = machine **nue** (démarrer un service, réseau compris, est une décision
  d'admin à coût → défaut OFF ; l'étudiant active en TP ; seuls restent `marionnet-relay` + `getty` +
  cœur systemd + `linuxlogo`). PASS 1 (unités natives) : parcourt `multi-user.target.wants`, retire le
  symlink de **tous** les `*.target.wants/` (car ex. `networking.service` est aussi
  `WantedBy=network-online.target`). PASS 2 (SysV-only sans unité native, ex. `isc-dhcp-server`, tirés
  par `/etc/rc*.d` via `systemd-sysv-generator`) : `update-rc.d remove`. Trois sous-bugs corrigés en
  route : `systemctl --root disable` **no-op offline** (host refuse le chroot) → `rm` direct du symlink ;
  guard `[[ -e ]]` **suivait le symlink absolu invité et le résolvait contre l'hôte** (faux pour tout
  daemon absent de l'hôte : babeld/named/nmbd…) → `[[ -e || -L ]]` ; la 1ʳᵉ version ne nettoyait que
  `multi-user.target.wants` (networking survivait) → balayage multi-target + SysV. **(#4)**
  `fix_etc_inittab` **active `getty@tty0`** offline sous systemd : `console=tty0` (ép. 4) est
  **nécessaire mais insuffisant** — systemd ne démarre `getty@tty0` que si l'unité est explicitement
  activée. **(#A)** dans le tester, `kernel_series_of` corrigé (le `realpath` du kernel résolvait le
  symlink `linux-6.12.95` → série perdue) : dérivation par regex `linux-[0-9]+\.[0-9]+`. Validation :
  image finale **nue** (`multi-user.target.wants` = `marionnet-relay` seul ; 0 networking ; 0
  isc-dhcp-server), boot atteint **`login:` sur con0** sans aucun contournement. **Signal à traiter
  côté chantier NOYAU** (pas rootfs) : flake UML 6.12 non déterministe (~1 boot/3)
  `systemd-executor: libcrypt.so.1: cannot apply additional memory protection after relocation: Error 38`
  (ENOSYS mprotect RELRO) — même famille que `epoll_wait: Function not implemented` (libuv/named).
  **Volet OCaml (verrou C) toujours en attente de la toolchain 4.13.1** : `console=tty0` de l'ép. 4 est
  désormais confirmé au boot, mais `simulation_level.ml` non recompilé.
- **2026-07-10** — épisode 8 (`pupisto.debian.sh` ; `docs/kernel-rootfs-refresh.details.md` nouveau) :
  **timers systemd de maintenance désactivés** (suite du durcissement « machine nue »). Les passes 1-2
  de `prevent_non_vital_services_from_starting` traitaient les *services* ; 8 *timers* survivaient sous
  `timers.target.wants/` (apt-daily, apt-daily-upgrade, dpkg-db-backup, e2scrub_all, fstrim,
  lighttpd-maint, logrotate, man-db). Tous ont `Persistent=true` → rattrapage **au boot** (horloge VM
  en retard) : rafale de maintenance au démarrage. Analyse timer-par-timer et décision (les 8 ÉLIMINÉS,
  y compris `logrotate` le seul discutable) archivées dans **`docs/kernel-rootfs-refresh.details.md`**
  (fichier de traces, non chargé en contexte par défaut). Implémentation : **passe 3** symétrique au
  pass 1 (balaye `timers.target.wants/`, `rm` du symlink, offline-safe, whitelist vide). Vérifié :
  `bash -n` OK + dry-run capte exactement les 8 sur le rootfs de la dernière image. **Boot NON re-testé**
  (exige un rebuild image ~1h sudo/réseau, côté Jean).
- **2026-07-10** — épisode 9 (`uml/pupisto.tester/pupisto.tester.sh`, `.gitignore`,
  `docs/kernel-rootfs-refresh.details.md`) : **outillage de test autonome + PoC « architecture C »**
  (déport X11 sur noyau vanilla, ghostification par network namespace).
  **`-A/--auto-network-by-eth42`** : tap hôte↔invité sur eth42 + sshd, **unique par instance** (octet K
  libre → `mnt-tapK`/`tester-K`/`172.23.K.{1,254}`, clé ed25519 auto gitignorée, règle sudoers NOPASSWD
  scopée `mnt-tap*` auto-provisionnée) → **SSH sans mot de passe** dans la VM pour des tests sans
  intervention humaine.
  **`-X/--display`** entièrement **réécrit sur l'architecture C** (l'ancien transport X11 par port série
  est abandonné : multiplexage impossible + transport hôte→invité bloqué). Principe : eth42 reste un lien
  réseau de service mais est **ghostifié dans l'invité en le déplaçant dans un network namespace caché**
  (`marionnet-mgmt`) — le `ip a` de l'étudiant ne le liste plus ; un `socat` (via `systemd-run`, survit au
  service) y relaie le display `:0` (socket Unix *pathname*, visible cross-netns) vers le pont X hôte sur
  eth42 ; côté hôte `socat TCP:172.23.K.254:6000 → socket X` + `xhost +local:`. **X11 multiplexe
  nativement** — plus de mur série. **Idée directrice de Jean (« idée n°2 »)** : remplacer le patch noyau
  de ghostification par un simple déplacement d'eth42 dans un namespace de l'invité — masquage
  **pédagogique** (pas anti-root), atteint l'objectif « noyau vanilla » sans patch, plus léger et débogable.
  Audits confirmant la voie : **C1** (eth42/ip42 ne servent qu'au X11 : `xhost`, tap, adresse de display) ;
  **C2** (la ghostification patch — invisibilité ioctl/netlink/proc/netfilter même au root — est remplacée
  par le netns, mêmes surfaces pour l'étudiant, patch noyau **et** outil C `ethghost` supprimés).
  Détails, traces et décisions dans `docs/kernel-rootfs-refresh.details.md`.
  **Validation** : mécanisme netns validé (eth42 déplaçable, invisible du netns racine, fonctionnel depuis
  mgmt) ; volet invité rejoué en autonomie (relais `active`, socket créé) ; **`xeyes` s'affiche sur l'écran
  hôte** ⇒ architecture C prouvée bout-en-bout. **`wireshark` crash** = bug **noyau UML 6.12.95**
  (`BUG: Bad page map … file:PACKET mmap:sock_mmap`, ring `PACKET_MMAP`), **orthogonal à C**, non
  reproductible via `dumpcap` CLI (5 configs) → **chantier NOYAU** (bloque la capture live, comme vwifi).
  **Piste ouverte, non appliquée — « idée n°1 » de Jean** : faire tourner Marionnet dans une sandbox
  **user-namespaces** pour le rendre **rootless** et **supprimer le rôle privilégié de `marionnet_daemon`**
  (le réseau inter-équipements VDE est déjà userspace) — chantier séparé, découplé de X11.
- **2026-07-10** — fix build (`7bca541`, `bin/{disk,machine,simulation_level,user_level}.mli` + `disk.ml`) :
  **recompilation de l'épisode 4**. La toolchain OCaml 4.13.1 (camlp4) ayant été restaurée (switch opam
  réinstallé), le build a révélé que `b245677` avait ajouté aux `.ml` la méthode `get_init_system` /
  `init_system_of` et le paramètre optionnel `?init_system` **sans mettre à jour les `.mli`** → compilation
  séparée cassée. Correctif : exposer ces membres dans `user_level.mli`, `machine.mli` et les 3 constructeurs
  de classe de `simulation_level.mli` (`uml_process`, `machine_or_router`, `…_with_accessory_processes`).
  **`dune build @all` → rc=0**, `marionnet.exe` se linke (`marionnet_daemon.exe` n'est pas une cible câblée
  par le dune actuel — chantier « finitions », sans rapport). **Reste du volet OCaml** : porter la table
  `BOOT_QUIRKS` et **aligner le mécanisme netns X11 (architecture C)** côté Marionnet.
  Par ailleurs, **recherche approfondie des paquets pédagogiques** (TP univ/école d'ing., réseau > système >
  cybersécurité > programmation) archivée dans `docs/recherche-paquets-pedagogiques-trixie.md` : base pour
  affiner `package_catalog.trixie.selection` (volet « contenu de l'image », distinct).
- **2026-07-10** — épisode 10 (`package_catalog.trixie.selection`) : **contenu de l'image affiné**
  depuis la recherche pédagogique. Réconciliation recherche ↔ sélection validée contre l'index
  `dists/trixie/main/binary-amd64/Packages.xz` (68 755 paquets) : le socle réseau/analyse était déjà
  complet ; **`nikto` et `zaproxy` (OWASP ZAP) sont absents de trixie/main** (tranche par le négatif la
  piste « alternative libre à Burp », cohérent avec l'écartement de Burp/Metasploit). **147 → 162
  paquets** : dé-commentage de `iptables` (syntaxe des TP pare-feu) et `wget` ; ajout de 13 lignes au
  motif « 2026 addition » — réseau `openvpn` ; couche cyber **complète** (arbitrage Jean) `hydra`,
  `sqlmap`, `sleuthkit`, `binwalk`, `aircrack-ng` (offline seul, pas de mode monitor en UML),
  `ettercap-text-only` (variante sans X11) ; prog `python3-venv`, `rustc`, `cargo`, `geany` (éditeur GUI
  léger — seule entorse assumée à X11-minimal), éditeurs console `nano`, `emacs-nox`. `g++` écarté
  (redondant via `build-essential`). Insertion à la place alphabétique (fichier trié par nom, `#`
  ignoré, locale par défaut) ; diff = 15 ins/2 del sans réordonnancement parasite. **Build/boot NON
  re-testés** (rebuild image ~1h sudo/réseau, côté Jean ; un nom inexistant en main serait fatal à
  l'`apt-get install` — d'où la validation préalable contre l'index).
- **2026-07-11** — épisode 14 (`pupisto.debian.sh`, `uml/kernel/CONFIG-modern-base`) : **garde-fou
  features noyau + fragment labo**. Diagnostic des deux défauts de la dernière image trixie :
  **(1) iptables** échoue (`Failed to initialize nft: Protocol not supported`) car le `.config` gelé
  a `# CONFIG_NETFILTER is not set` (donc pas de `NF_TABLES` pour le backend `iptables-nft` de trixie ;
  le legacy manquerait aussi `x_tables`) — **défaut noyau, pas rootfs** ; **(2) wireshark** crashe la
  VM (`BUG: Bad page map … PACKET mmap:sock_mmap`) : `CONFIG_PACKET=y` est **déjà** présent → c'est un
  **bug mémoire UML sur le ring `PACKET_MMAP`**, **pas** un toggle de config (investigation séparée, cf.
  bullet « Chantier NOYAU »). Le `.config` gelé s'avère aussi privé de `BRIDGE`, `VLAN_8021Q`,
  `NET_SCHED`, `VETH`, et a `TUN`/`PPP` en `=m`. **Automatisation demandée** (« que tous les binaires
  installés fassent des hypothèses correctes sur le noyau ») : une **Map bashbricks
  `KERNEL_REQUIREMENTS`** dans `pupisto.debian.sh` (`paquet → CONFIG_* requis en =y`, **source de vérité
  unique** qui documente aussi le fragment) + `check_kernel_features_for_selection`, lancé après
  `make_or_link_the_kernel`, qui lit le `.config` apparié et **fait échouer le build (fatal**, override
  `MARIONNET_KERNEL_CHECK=warn|off`**)** si un paquet **sélectionné** (pilotage par la `.selection`)
  exige un symbole absent. **=y et non =m** : ces images UML ne chargent pas de modules au runtime.
  Logique **validée** contre le `.config` courant (harnais) : **13 violations** exactes (iptables×5,
  nftables×2, bridge-utils, vlan, iproute2×2 — `NET_NS` déjà =y —, openvpn, ppp), tcpdump/wireshark/tshark
  OK (`PACKET=y`). **Fragment labo** (=y) appendu à `CONFIG-modern-base` (sémantique kconfig « dernière
  occurrence gagne », idiome `echo >> .config` de `pupisto.kernel.sh`) : netfilter core + nftables
  (`NF_TABLES`, `NF_TABLES_INET/IPV4/IPV6`, `NFT_CT/NAT/COMPAT`, `NETFILTER_XTABLES`, `NF_CONNTRACK`,
  `NF_NAT`, `NETFILTER_ADVANCED`), `BRIDGE`, `VLAN_8021Q`, `NET_SCHED`+`NET_SCH_NETEM/HTB`, `VETH`,
  `TUN=y`, `PPP=y`. Le gelé **`CONFIG-6.12.95` a été renommé `.bak`** dans cet épisode (le chemin de
  priorité 1 est un match **exact**, pas un glob → le build retombe sur le seed + `olddefconfig`, dep-safe).
  **RESTE (rebuild = Jean)** : régénérer le noyau (`pupisto.kernel` : `cp` seed → `make olddefconfig`),
  **re-geler** le `.config` produit comme `CONFIG-6.12.95` et le committer ; le check ép.14 **valide**
  alors le résultat (et signale toute dépendance Kconfig oubliée). `bash -n` OK ; effet sur l'image
  **non** vérifié sans le rebuild.
- **2026-07-11** — épisode 15 (`uml/kernel/CONFIG-modern-base`, `CONFIG-6.12.95` re-gelé,
  `pupisto.debian.sh`) : **noyau reconstruit + pare-feu complet + IPv6, re-gel**. Rebuild
  `./pupisto.kernel.sh 6.12.95` (seed + `olddefconfig`, rc=0, binaire `linux` 7,7 Mo UML). **IPv6**
  ajouté au seed (`CONFIG_IPV6=y`) — TP dual-stack **et** dépendance qui débloque la famille `inet` de
  nftables (`NF_TABLES_INET`, que `olddefconfig` droppait sans IPv6). Puis, **vérification par le script
  `uml/kernel/check-inconsistencies.sh`** (comparaison de configs via bashbricks, Jean) : l'ép.14 ne
  gardait que le **cadre** netfilter → les **expressions/matches/cibles pare-feu** (`reject`, `log`,
  `masquerade`, `-m state/-m multiport`, `-j LOG`, iptables-legacy entier) étaient **OFF** → règles
  inutilisables malgré le cadre. Périmètre **complet** retenu (arbitrage Jean) : expressions nft
  (REJECT/REJECT_INET/LOG/MASQ/LIMIT/REDIR), matches/cibles xtables (STATE/CONNTRACK/MULTIPORT/LIMIT/MAC,
  LOG/MASQUERADE, XT_NAT), **iptables-legacy IPv4+IPv6** (IP{,6}_NF_IPTABLES/FILTER/NAT/MANGLE +
  TARGET_REJECT/MASQUERADE) — tous =y au seed **et** ajoutés au map `KERNEL_REQUIREMENTS` (le check les
  garde). 3 symboles inexistants en 6.12 écartés après vérif du Kconfig de l'arbre : `NFT_COUNTER` (le
  `counter` est intégré au core nf_tables), `NFT_FIB_INET` (familles fib hors périmètre), et le
  fantomatique `NETFILTER_XT_TARGET_REJECT` (le reject vient de `IP{,6}_NF_TARGET_REJECT`/`NFT_REJECT`).
  Extras `=m→=y` (capacités que l'image legacy — tout-`=y` — avait et que le seed modulaire avait
  perdues, inutilisables faute de `/lib/modules` dans le rootfs) : `BLK_DEV_LOOP`, `DUMMY`, `ISO9660_FS`.
  **Découverte structurelle** : pupisto ne fait **aucun `modules_install`** dans le rootfs, or le build
  produit **22 `.ko` orphelins** (`CONFIG_MODULES=y`) → toute feature `=m` est de facto indisponible dans
  l'invité, ce qui **justifie la politique =y** du check (question séparée : `CONFIG_MODULES=n` ou
  installer les modules). `CONFIG-6.12.95` **re-gelé** depuis
  `_build.linux-6.12.95.2026-07-11.19h04.19248/.config`, `.bak` supprimé. **Check ép.14 : 30/30
  symboles =y, 0 violation.** **Preuve runtime** (`iptables -L`, `nft list ruleset` dans une VM) = à
  faire au prochain rebuild image + boot-test.
- **2026-07-12** — épisode 16 (`uml/pupisto.debian/pupisto.debian.sh`) : **contournement du crash
  wireshark (bug noyau UML `PACKET_MMAP`)**. Après rebuild ép.15, `xeyes` + `iptables` validés runtime,
  mais **wireshark crashe la VM** (`BUG: Bad page map … file:PACKET mmap:sock_mmap` → `Bad rss-counter` →
  panic à 512M, `dumpcap` aborté mais VM vivante à 2G). **Débogage systématique + pilotage autonome via
  `pupisto.tester.sh -A`** (SSH par `tester_key`, cf. mémoire) : cause racine = corruption de la
  comptabilité rmap (`folio_mapcount<0` au `zap`, mm/memory.c l.1521, inversion FILE↔ANON) des pages du
  ring `PACKET_MMAP` sous UML — activateur structurel : **UML n'a pas `ARCH_HAS_PTE_SPECIAL`** (matrice
  noyau : `um` = « TODO » ; absent du `.config` 6.12.95). **H1 (fallback `vzalloc`/fragmentation) et H2
  (ordre du ring) réfutées** (2G, `-B 512 MiB`, 29 MiB libres, rings concurrents → jamais reproduit en
  `-A` headless). **Isolé** : le **seul** déclencheur est le **poller d'interfaces de l'écran d'accueil**
  de wireshark (`dumpcap -S`, qui ouvre un ring AF_PACKET sur **toutes** les interfaces d'un coup) ; le
  ring de capture d'**une** interface est sain (validé `-X` : `wireshark -o capture.no_interface_load:TRUE
  -k -i lo` → pas de crash), et le multi-interfaces aussi (validé `-X`, `-i lo -i wsdummy`). **Piste 1
  « forcer non-mmap » écartée** (libpcap moderne = plus de repli `read()` ; fifo inutile car le crash est
  à l'énumération, pas à la capture). **Fix retenu** : désactiver le poller via la préférence
  **`capture.no_interface_load: TRUE`** + fournir soi-même les interfaces UP en `-k -i`. Packaging dans
  `pupisto.debian.sh` : (1) `jq` ajouté à `MANDATORY_PACKAGES` ; (2) `install_wireshark_marionnet_wrapper`
  pose la **préf système** `/usr/share/wireshark/preferences` (filet anti-`apt upgrade` : fichier non
  possédé par le paquet, donc jamais écrasé), **fabrique** (heredoc) `/usr/bin/wireshark.marionnet.sh`
  (no-arg → toutes interfaces UP via `jq` ; `IFACE` → cette interface ; fichier/option → délégué au vrai
  binaire ; toujours `-o capture.no_interface_load:TRUE`), **déplace** `wireshark`→`wireshark.real` et
  **symlink** `wireshark`→le wrapper. Idempotent (garde `[[ ! -L ]]`), `bash -n` OK, routing + idempotence
  testés. **Contournement** (cause racine noyau intacte = piste 2, non nécessaire tant que ça suffit).
  Rebuild image end-to-end en cours (Jean).
- **2026-07-12** — épisode 17 (`uml/pupisto.tester/pupisto.tester.sh`, `uml/pupisto.debian/pupisto.debian.sh`) :
  **modes de boot du testeur orthogonalisés + fix racine de la corruption du login console**.
  L'ancien `-A` monolithique (tap+eth0 **et** pilotage) mélangeait deux préoccupations et cassait le
  login (`</dev/null &` ⇒ getty lit EOF). **Décomposition** : `-A/--auto-network-by-eth0` = **seulement**
  le couple (tap hôte, eth0 invité), défait à la sortie ; nouveau `-S/--ssh-only` = pilotage headless
  autonome (implique `-A` + sshd + clé `tester_key` + arrière-plan + `READY`) ; nouveau `-c/--console` =
  console interactive sur le terminal courant sans xterm (stdin ouvert ⇒ vrai `login:`), sans timeout ;
  `-H/--headless` reste scriptable/CI ; **`-X` implique désormais xterm** (bug corrigé : `-X -A` ne
  lançait pas le xterm). Renommage `SSH_*`→`ETH0_*`/`X11_*` ; `-X` et `-A` prennent chacun un octet libre
  et **coexistent**. **Cause racine du login corrompu** (`tester login: ^[[47;1R…` polluant le nom
  d'utilisateur) enfin isolée après plusieurs fausses pistes (`/etc/issue`, `linuxlogo`, `agetty` — tous
  **innocentés**, y compris via un quirk relais `tester-console` de diagnostic, retiré) : c'est **systemd
  getty** qui, `TTYColumns`/`TTYRows` non définis, **sonde la taille** de la console UML sans dimension
  (`con0`) par une séquence ANSI (`ESC[6n`) ; la réponse du terminal (`ESC[<row>;<col>R`) atterrit dans le
  prompt (`systemd.exec(5)`). **Fix gravé dans `pupisto.debian.sh`** (`fix_etc_inittab`, à l'activation de
  `getty@tty0`) : drop-in `getty@tty0.service.d/console-size.conf` = `TTYColumns=80`/`TTYRows=24` ⇒ plus de
  sonde, **login propre (validé en direct par Jean)**. **Reste un décalage d'affichage** (le prompt
  n'apparaît qu'après ENTER) = quirk du canal console `fd` d'UML (terminal sans dimension ni discipline de
  ligne propre) — **accepté comme connu et documenté** (aide `-c` + commentaire de branche) ; `-X` (pty
  xterm réel) reste fluide. `bash -n` OK sur les deux fichiers. **Le fix `TTYColumns` exige un rebuild**
  de l'image pour prendre effet.
- **2026-07-16** — épisode 18 (`uml/pupisto.kernel/pupisto.kernel.sh`, `uml/pupisto.kernel/Makefile`) :
  **rejeu non-interactif des configs gelées**. Sur la nouvelle plateforme de dev/test (64 cœurs,
  binutils avec support zstd), `./pupisto.kernel.sh 6.12.95` **bloquait sur un prompt kconfig**
  (« Restart config… », `choice[1-3?]:`, sous le `tee` d'auto-journalisation) : la branche
  « pre-built config » copiait `CONFIG-6.12.95` **sans réconciliation**, et le `make ARCH=um`
  suivant redécouvrait `DEBUG_INFO_COMPRESSED_ZSTD (NEW)` — symbole dont la **visibilité dépend
  de la toolchain hôte** (absent lors du gel ép. 15). Un `.config` gelé ne rejoue tel quel que
  sur la toolchain qui l'a gelé. Fix : pour les noyaux ≥ 5, `make olddefconfig ARCH=um` après le
  `cp` (choix gelés conservés, symboles nouveaux → défaut) + affichage **non fatal** du diff vs
  le gelé (`scripts/diffconfig`) pour l'audit de reproductibilité ; série legacy 3.x inchangée.
  En passant : doublon `…/kernel/kernel` corrigé dans le message « No patch found » ; règle
  pattern du `Makefile` étendue à `5.% 6.%` (`make 6.12.95` matche désormais). **Preuve** : run
  end-to-end `Success.` rc=0 en 31,7 s wall (`_build.linux-6.12.95.2026-07-16.12h48.13713`,
  binaire 8,07 Mo) ; diff vs gelé = trace gcc 12.4→13.3 + `DEBUG_INFO_COMPRESSED_ZSTD n` seul →
  **re-gel de `CONFIG-6.12.95` inutile** (aucune divergence fonctionnelle).
- **2026-07-16** — épisode 19 (`uml/pupisto.debian/Makefile`, `uml/pupisto.debian/Makefile.d/install.last-built-couple.sh`
  nouveau) : **installer le dernier couple (noyau, image) construit** sur la plateforme de dev/test.
  Nouvelle cible `make install` (+ `install-dry-run`, `PREFIX ?= /usr/local`) déléguant à un script
  `Makefile.d/install.last-built-couple.sh` inspiré de la logique `download_marionnet_kernels_and_filesystems`
  de `useful-scripts/marionnet_from_scratch` (mais **depuis le build local**, pas depuis marionnet.org).
  Détection = plus récent `_build.*` **finalisé** (présence d'un `machine-*.conf` → ignore le build
  avorté au debootstrap) ; résout l'image `machine-<distro>-<SUM>`(+`.conf`, +`_variants/` si présent)
  et le noyau via le symlink `linux-<ver>` → binaire `linux`/`vmlinux` + `.config` de l'arbre
  `pupisto.kernel/`. Installe sous `$PREFIX/share/marionnet/{kernels,filesystems}/` via `sudo` (comme
  `marionnet_from_scratch`), noyau en `kernels/linux-<ver>`(+`.config`) — **sans `-ghost`** (trixie =
  `GHOSTIFICATION=netns`, noyau non patché ; l'épithète `6.12.95` satisfait `SUPPORTED_KERNELS='/6.12.95/'`),
  et **restaure le MTIME** de l'image lu dans son `.conf` (impératif de partage de projets documenté
  dans le conf). Script **générique** (distro/version/SUM déduits des noms), tolère `--no-kernel`
  (image seule), `--dry-run`, `BUILD_DIR` explicite. **Preuve** : `make install` réel — image
  `machine-debian-trixie-36697` (5 379 194 880 o, MTIME `@1784200177` restauré exact) + noyau
  `linux-6.12.95` (ELF x86-64, +x) + `.config` posés dans `/usr/local/share/marionnet/`, coexistant
  avec le legacy `linux-3.2.64-ghost` ; build incomplet `12h56` correctement ignoré.
- **2026-07-16** — épisode 20 (`bin/simulation_level.ml`, `uml/pupisto.debian/pupisto.debian.sh`,
  `uml/pupisto.debian/pupisto.debian.sh.files/marionnet-relay.trixie`) : **premier run GUI trixie
  propre** — deux régressions systemd corrigées, observées au lancement d'une machine trixie par la
  GUI. **(1) Consoles surnuméraires** : au lieu de la seule console demandée (`console_no=1`), trois
  xterms s'ouvraient (#0 login, #1 login dupliqué, #6 vide). Racine : la coordination boot (nombre de
  gettys) reposait encore sur des mécanismes **SysV** (`/etc/inittab`) qu'un invité systemd ignore.
  Le #1 dupliqué et le #6 vide venaient de l'**autovt de logind** (`NAutoVTs=6`/`ReserveVT=6` par
  défaut, confirmé par `loginctl show-seat` dans la VM) qui réserve tty1..tty6 ; par-dessus, `con=xterm`
  fait ouvrir à UML **un xterm par console VT** dès que le noyau active tty1 en VT de premier plan
  (`console=tty0`), indépendamment de tout getty — et l'invité ne peut pas rétracter une console UML
  déjà ouverte. **Correctifs en trois couches cohérentes** : (a) *build* (`pupisto.debian.sh`,
  `fix_etc_inittab`) — drop-in `logind.conf.d/marionnet-no-autovt.conf` = `NAutoVTs=0`/`ReserveVT=0`
  (lu tôt par logind, avant le relay ⇒ doit être gravé au build) ; (b) *cmdline noyau*
  (`simulation_level.ml`) — remplacement du `con=xterm` global par `con=none con0..con(N-1)=xterm`
  **borné à `console_no`** (une console `conN=` spécifique l'emporte sur le `con=` général, HOWTO UML),
  rendant `console_no` enfin **autoritaire au niveau UML** — c'est ce point qui supprime l'xterm vide de
  tty1, que le relay ne pouvait pas fermer (concrétise le `con0=` laissé en commentaire mort par
  l'auteur ; miroir du `con=none` éprouvé de wheezy) ; (c) *relay systemd*
  (`marionnet-relay.trixie`) — pilotage explicite des gettys par `console_no` (`systemctl start
  getty@tty1..N-1`, `stop` au-delà), la logique inittab SysV préservée dans le `else`. **(2) La
  terminaison propre relançait la machine** : la GUI arrête proprement par `uml_mconsole <umid> cad`
  (Ctrl-Alt-Del, `simulation_level.ml#gracefully_terminate`) ; sous SysV `ctrlaltdel` était mappé sur
  `/sbin/halt`, mais sous systemd Ctrl-Alt-Del active `ctrl-alt-del.target`, **aliasé `reboot.target`**
  par défaut ⇒ la VM redémarrait au lieu de s'arrêter (le bouton « débrancher »/SIGKILL, lui,
  fonctionnait). Fix (relay) : `ln -sf poweroff.target /etc/systemd/system/ctrl-alt-del.target`
  (équivalent systemd du `ctrlaltdel:/sbin/halt` de buildroot). **Preuve runtime (Jean, GUI, après
  rebuild image + rebuild dune)** : `dune build` rc=0 ; run GUI trixie → **une seule console #0
  (login)**, plus d'xterm parasite ; **bouton terminer → poweroff propre** (log : `cad` réussi puis
  `waitpid … exited` immédiat, pas de boucle de reboot ni recours au SIGKILL de garde à 30 s).
  `bash -n` OK sur les deux scripts. Note : la couche (b) n'exige qu'un rebuild dune ; (a) et (c)
  exigent un rebuild d'image (déjà fait).

- **2026-09-02** — épisode 21 (`bin/simulation_level.ml`,
  `Makefile.d/filesystem.prepare-snapshot-to-publish.sh`) : **le boot ne se terminait pas quand
  le prompt paraissait**. Signalé depuis la salle MarioNUM (image publiée
  `machine-debian-trixie-39212`) : les `[OK]` s'affichent **après** `m1 login:` et même après le
  login. **Mesuré dans l'invité** : `systemd-analyze blame` → `2min 956ms
  systemd-networkd-wait-online.service` (enabled, *failed*), `critical-chain` →
  `multi-user.target @26,7 s`, et `rpc-statd-notify.service` est le seul actif à vouloir
  `network-online.target`. Prompt à ~27 s, échec de l'attente à ~147 s : ce n'était pas un
  désordre d'affichage, c'était un boot qui traînait deux minutes.
  **Mesuré dans l'image** (`debugfs`, lecture seule) : trois liens portent **la même minute**,
  `multi-user.target.wants/systemd-networkd.service`,
  `network-online.target.wants/systemd-networkd-wait-online.service` et
  `sysinit.target.wants/systemd-network-generator.service` — 23-Aug-2026 14:51, quand tout le
  reste date du 16-Jul (le build pupisto). Un `systemctl enable systemd-networkd` fait pendant la
  session de mise à jour (`trixie-47362-update-and-tuning.mar`) a **traîné le guetteur avec lui** :
  l'unité que Debian livre le dit elle-même (`Also=systemd-networkd-wait-online.service`).
  Le passage à networkd était **voulu** — `/etc/systemd/network/10-eth0.network` demande `DHCP=yes`
  et la strophe `eth0` d'ifupdown est commentée — donc on garde networkd et **seul le guetteur**
  s'en va. `pupisto.debian.sh` est hors de cause (0 site n'y nomme networkd) : le défaut est entré
  par un réglage à la main, et il a été **figé et publié**.
  **Correctif en deux moitiés.** (a) `bin/simulation_level.ml` ajoute
  `systemd.mask=systemd-networkd-wait-online.service` à la ligne de commande de **tout** invité
  systemd — même mécanisme, et même raison, que le `systemd.mask=serial-getty@ttyS0.service`
  voisin (dont le commentaire mesure déjà « 90 seconds of boot waiting for a job that then
  fails »). Placé **hors** de la branche du masque getty (conditionnée à l'enregistrement des
  consoles *et* à un `console=` explicite) et **hors** de `boot_quirks` (indexé par série de noyau,
  alors que ce défaut n'en dépend pas) : une liste propre, gardée par le seul
  `init_system = "systemd"` — sous SysV un argument inconnu partirait en argument à `init`.
  (b) `filesystem.prepare-snapshot-to-publish.sh` **refuse** (rc 2) de publier un instantané qui
  active une unité connue pour coûter cher au boot, et **nomme le remède**
  (`systemctl mask …` dans l'invité, puis refaire l'instantané) au lieu de réparer en silence ;
  `--allow-slow-boot` pour le cas délibéré, `--check-image FILE` pour poser la question à une
  image déjà publiée. Lu par **`debugfs`**, donc **sans privilège** et même sous
  `--do-not-update-binary-list` ; `debugfs` absent ⇒ avertissement, pas verdict (on ne condamne
  pas pour n'avoir pas pu mesurer).
  **Mesuré ici, sur l'image et le noyau publiés** (`website-repo/download/…/1.0.x`, montés en
  `~/.marionnet/`, session pilotée par le canal) : la ligne de commande de l'UML porte bien
  `systemd.mask=systemd-networkd-wait-online.service` ; dans l'invité,
  `systemctl is-enabled` → **`masked-runtime`**, `is-active` → **`inactive`** ; le `boot.log` du
  hostfs ne contient **0** occurrence de `systemd-networkd-wait-online` et le boot entier tient en
  **~9 s** ; capture de la console : après `m1 login:`, **plus rien**. Garde-fou du publieur joué
  sur trois images réelles : **refus** sur la trixie publiée (avec le remède), **accepté** sur
  guignol et wheezy (sysv), **avertissement seul** avec `--allow-slow-boot`.
  `dune build` rc 0, `make check` rc 0.
  **Deux trouvailles versées à `docs/TODO.md`** : une machine ajoutée **par le canal** reçoit
  `memory_default = 48` (`bin/machine.ml:67`) sans jamais consulter le `MEMORY_SUGGESTED_SIZE=192`
  du `.conf` — que seul le **dialogue GUI** applique — et une trixie à 48 Mio **meurt d'OOM**
  (mesuré : `Out of memory: Killed process 111 (systemd-network)`) ; et `marionnet-relay.service`
  prend **16,5 s** dans le `blame` de la salle, `multi-user.target` n'étant atteint qu'à 26,7 s.
- **2026-09-02** — épisode 21 bis (`Makefile.d/filesystem.prepare-snapshot-to-publish.sh`) :
  **l'image propre existe, et la fabriquer a révélé un défaut du garde-fou.** `systemctl mask`
  pose `/etc/systemd/system/<unité> -> /dev/null` mais **ne retire pas** le lien d'activation
  sous `network-online.target.wants/` — or le garde-fou de l'épisode 21 ne regardait que ce
  lien : il aurait **refusé** une image réparée exactement comme il le conseille. *Un garde-fou
  que son propre remède ne satisfait pas est un défaut.* `boot_health_check` accepte donc
  désormais **les deux** issues : lien d'activation retiré (`disable`), **ou** unité masquée
  (`Fast link dest: "/dev/null"`, lu par `debugfs`).
  **L'image** a été produite en pilotant Marionnet par le canal, depuis l'image publiée
  `/usr/local/share/marionnet/filesystems/machine-debian-trixie-39212` : machine trixie à
  **256 Mio** (à 48, le défaut du canal, elle meurt d'OOM), `systemctl mask
  systemd-networkd-wait-online.service` par `exec`, **arrêt propre** (`stop`, `--state=off` en
  3,5 s), puis export de la variante par la commande **exacte** de la GUI
  (`cp --sparse=always`, `bin/treeview_history.ml:451-458`) et
  `filesystem.prepare-snapshot-to-publish.sh -y`.
  **Résultat, déposé dans `website-repo/download/marionnet-install.sh/1.0.x/`** :
  **`machine-debian-trixie-16341`** (5,4 Gio) + son `.conf` (`SUM=16341`,
  `MD5SUM=5f3d4fe3…`, `MTIME=1788385092`) + `filesystems_machine-debian-trixie-16341.tar.xz`
  (1,1 Gio), `SHA256SUMS` à 18 artefacts (1 calculé, 0 conservé). **Mesuré** : `sum` du fichier
  = **16341** = son nom ; `mtime` du disque = `MTIME` du `.conf` ; `sha256sum -c` réussi ; le
  masque est bien dans l'image (`debugfs` : `Fast link dest: "/dev/null"`) et **networkd,
  `10-eth0.network` et `systemd-networkd.service` sont intacts** ; garde-fou : **rc 0** sur la
  neuve, **rc 2** sur la 39212 ; boot réel de la neuve par Marionnet : **0** occurrence de
  l'unité dans le `boot.log`, console s'arrêtant sur `m1 login:`.
  **Ce qui n'est PAS mesuré** : un boot de cette image par un Marionnet **sans** le masque de la
  ligne de commande (c'est-à-dire la release installée en salle) — la preuve tiendrait à une
  reconstruction du binaire d'avant ; le masque dans `/etc` est en revanche celui que systemd
  lit, et le garde-fou (code indépendant) le constate. **Rien n'est mis en ligne** : la
  publication et la rétention de l'ancienne 39212 restent des gestes de l'auteur.

- **2026-09-03** — épisode 22 (`bin/treeview_history.ml`, `bin/control_server.ml`) :
  **`history-export`, le dernier geste du menu des états que le canal ne savait pas jouer.**
  Produire l'image `16341` depuis la `39212` (ép. 21 bis) a été piloté par le canal de bout en
  bout **sauf l'export de la variante**, fait avec un `cp` à la main : le canal a pour mandat de
  donner « les gestes de la GUI », et il en manquait un — celui dont sort toute image publiée.
  **Le nom vient de la famille** : `history`, `history-start`, `history-del`, `history-set`
  travaillent déjà sur ce treeview, avec pour identifiant le **nom du fichier COW** (unique, sans
  espace, publié par la lecture) ; `history-export <cow file> <variant name> [--force]` reprend le
  même préfixe, le même identifiant et le même prologue (`history_row_of_cow`). `export-variant`
  aurait fondé une famille d'un seul membre.
  **Une seule implémentation** : la mécanique déménage dans
  `Treeview_history#export_row_as_variant` — où va une variante
  (`Disk.user_export_dirname_of_prefixed_filesystem`), quel fichier est copié, et surtout
  `cp --sparse=always` (**mesuré** : 2,6 Mio réels pour 5,1 Gio apparents — une copie dense
  écrirait les 5,1) — et les **deux** appelants s'en servent : le dialogue du menu, qui ne garde
  que ce qu'une fenêtre sait faire (dire que ça a marché, ou pourquoi non), et le canal, qui
  répond en JSON. Les gardes ne sont pas inventées ici : machine allumée refusée par
  `can_startup` (le COW d'une machine en marche est un système de fichiers que personne n'a
  démonté), nom validé par `StrExtra.Class.identifierp ~allow_dash:()` — les deux conditions que
  la GUI porte déjà.
  **Une divergence, assumée** : le dialogue **écrase** une variante du même nom sans un mot ; le
  canal **refuse** sauf `--force`. Un humain qui choisit un nom voit le répertoire ; un script ne
  voit rien, et une variante est ce dont sort une image publiée. Le chemin GUI passe donc
  `~force:true` — son comportement est **inchangé**, ce qui était la condition pour partager le
  code sans faire passer une modification de GUI dans un épisode de canal.
  **Mesuré** (session pilotée, image `machine-debian-trixie-16341`) : `help history-export`
  publie sa syntaxe (invariant : la grammaire a une seule source de vérité, le serveur) ; refus
  sur machine **allumée**, avec les mots de la GUI ; refus d'un nom **invalide** ; export
  **accepté** (JSON `node`/`state`/`variant`/`path`/`bytes`) ; **refus** au ré-export, **accepté**
  avec `--force` ; fichier **creux** (`du` 2,6 Mio contre 5,1 Gio apparents). `dune build` rc 0,
  `make check` rc 0.
  **Piège de mesure payé ici** : un état n'est **pas** la racine de l'arbre. `history m1` rend un
  **forêt** — la racine porte le nom de la machine et un COW qui n'existe pas encore, les états
  sont dans ses `children` — et mon premier essai a lu `rows[0]`, d'où un « le fichier n'existe
  pas » qui accusait le verbe alors qu'il disait vrai. C'est aussi ce que dit, depuis toujours, le
  message d'erreur du dialogue : *« you didn't select the machine disk but the machine itself
  (you should expand the tree) »*.

- **2026-09-03** — épisode 23 (`Makefile.d/filesystem.update-published-image.sh`,
  `bin/user_level.ml`) : **mettre à jour une image publiée devient une commande.**

  ```
  Makefile.d/filesystem.update-published-image.sh --image machine-debian-trixie-39212 \
      --in-guest 'systemctl mask systemd-networkd-wait-online.service'
  ```

  Le script enchaîne ce que l'ép. 21 bis avait fait à la main, et **les six pièges deviennent du
  code exécuté** : (1) le binaire de `_build` lit le préfixe *testing*, donc l'image et le noyau
  sont rendus visibles par des liens dans `~/.marionnet/` — retirés en sortant, et **seulement
  ceux qu'il a créés** ; (2) `Disk` filtre toute distribution sans noyau supporté **installé**,
  d'où les noyaux du répertoire de release liés eux aussi ; (3) la mémoire est lue dans le
  `.conf` (`MEMORY_SUGGESTED_SIZE`) et non laissée aux 48 Mio du canal, qui tuent une trixie ;
  (4) l'export passe par `history-export` (ép. 22), donc **aucun `cp` ici** ; (5) la copie creuse
  appartient au verbe ; (6) `stop` + `wait --state=off` avant l'export, jamais `poweroff`.
  **Pas de bashbricks**, comme les quatre autres scripts de cette famille : ce qu'il fait —
  écrire une ligne sur une socket, lire un objet JSON — est `socat` et `jq`, tous deux déjà
  dépendances de Marionnet.
  **À ne pas défaire** : une commande d'invité qui échoue **arrête tout avant l'export** (une
  image changée à moitié ne devient pas un artefact publié) ; une image `router-*` est refusée
  en disant pourquoi (c'est un **lien** vers l'image machine) ; et le script **ne publie pas en
  ligne** — il s'arrête au répertoire de release.

  **Le septième piège, trouvé par le banc et corrigé à sa source.** Le premier essai a exporté
  l'état d'un **guignol** dans le répertoire de variantes d'une **trixie**. Mesuré :
  `add machine m1 --distrib=guignol-18474` rend bien `distrib = guignol-18474`, mais la ligne
  d'historique — racine **et** enfant — porte `machine-debian-trixie-16341`, le filesystem *par
  défaut* : le canal **construit** la machine puis **applique** le champ, et `set_epithet`
  (`bin/user_level.ml`) ne touchait pas au treeview. Or ce champ est **fonctionnel** : c'est lui
  qui dit où va une variante. Correctif à la source : `set_epithet` appelle désormais la
  redirection **que le chemin d'import utilise déjà**
  (`redirect_history_rows_to_distrib`), avec **la garde qu'il porte déjà** — seulement si le
  composant n'a **aucun état COW** dans le projet, un état étant lié à son fichier de base
  (`mtime` compris). Après correctif : racine et enfant portent `machine-guignol-18474`.

  **Mesuré, sur guignol (12 Mio, ~1 min — c'est tout l'intérêt du banc)** : les 4 refus
  préalables (sans `--image`, image `router-*`, sans geste d'invité, image inexistante) tombent
  **avant** tout démarrage ; chaîne complète `machine-guignol-18474` → **`machine-guignol-03149`**
  + `.conf` + `.tar.xz` (13 Mio) + `SHA256SUMS`, dans un `--output-dir` temporaire — le
  répertoire de release n'est pas un bac à sable ; `sum` = **03149** = le nom, `mtime` = `MTIME`,
  `sha256sum -c` réussi ; la marque déposée dans l'invité est **dans** l'image neuve et
  **absente** de l'ancienne (`debugfs`) ; **discriminance** : `--in-guest 'false'` sort en **rc 2**
  et **aucune variante n'est créée**. `dune build` rc 0, `make check` rc 0.

- **2026-09-03** — épisode 24 (`bin/user_level.ml{,.mli}`, `bin/machine.ml{,.mli}`,
  `bin/router.ml`, `bin/control_server.ml`) : **la mémoire que l'image réclame, là où le canal la
  manquait.** `add machine` donnait `memory_default = 48` (`bin/machine.ml:67`), une constante qui
  précède les filesystems qu'on livre, sans jamais lire le `MEMORY_SUGGESTED_SIZE` du `.conf`
  (192 pour trixie, 24 pour guignol) — que **seul le dialogue GUI** appliquait, dans son callback
  `on_distrib_change`. Mesuré à l'ép. 21 : une trixie créée par le canal **meurt d'OOM** et ne
  répond plus, ce qui ressemble à un gel.
  **Le site était déjà écrit à côté** : `cmd_add` finit par `adjust_kernel_after_distrib_change`,
  dont le commentaire dit *« Realign before answering, so that `add` alone yields a bootable
  component »* — une machine qui meurt d'OOM ne l'est pas davantage. D'où
  `adjust_memory_to_distrib`, son jumeau, au même endroit. **Le nom n'est pas
  `..._after_distrib_change`, et c'est le propos** : l'ajustement vaut pour le filesystem que le
  composant **porte au final**, qu'il vienne de `--distrib=` ou du défaut choisi par le
  constructeur — un simple `add machine` sur un hôte dont le défaut est une trixie mourait
  pareillement.
  **Le chemin de lecture aussi** : le canal ne parle pas à `Disk`, il passe par les accesseurs en
  lecture seule d'`editable` (`supported_kernels_if_any`, `installed_distribs_if_any`,
  `variants_of_distrib_if_any`) ; le quatrième de la famille, `memory_suggested_size_if_any`, est
  ajouté avec la même forme (`None` sur la classe de base, redéfini dans `machine.ml`/`router.ml`,
  gardé contre un épithète non installé) et déclaré dans les `.mli` (5 occurrences dans
  `user_level.mli`, 1 dans `machine.mli`).
  **À ne pas défaire** : (1) `--memory=N` **gagne toujours** — une valeur explicite est une
  intention, et ce canal ne défait pas les intentions ; (2) `set <n> distrib` n'ajuste **pas** la
  mémoire, alors que la GUI réécrit sa case à chaque changement : un script qui a écrit
  `set m1 memory 512` avant ne doit pas se le faire effacer en silence ; (3) charger un `.mar` ne
  passe ni par l'un ni par l'autre, donc une mémoire enregistrée reste souveraine.
  **Mesuré** : `guignol-18474` → **24**, `debian-trixie-16341` → **192**, `--memory=64` → **64**,
  `add machine` sans distrib (défaut trixie) → **192**, `add router` inchangé ; **discriminance**
  sur le binaire d'avant (`git stash` + rebuild) → **48 partout** ; et le boot qui motivait tout :
  une trixie créée **sans** `--memory` démarre et répond à `exec` (là où elle mourait d'OOM).
  `dune build` rc 0, `make check` rc 0. L'entrée correspondante de `docs/TODO.md` **disparaît**.

- **2026-09-03** — épisode 25 (mesure seule, sans code) : **les ~7 s de `marionnet-relay.service`,
  et ce que la mesure élimine déjà.** Sur cette machine, image publiée
  `machine-debian-trixie-16341` : le relais coûte **7,264 s** avec `--debug` et **6,899 s** sans,
  pour un `multi-user.target` à **11,0 s** — l'homologue des 16,5 s / 26,7 s de la salle, à
  l'échelle de la machine près. **Trois choses sont acquises** : (a) *ce n'est pas la trace* — le
  relais journalise **324** lignes sous `--debug` contre **45** sans, pour la **même durée** ;
  (b) *aucun geste ne bloque à lui seul* — pas un écart de 2 s entre deux lignes tracées ;
  (c) *une part est nommée* — un **`daemon-reload` de systemd à 1,30 s**, ~19 % du total.
  La suite est **instrumentale** (un `PS4` portant `$EPOCHREALTIME` pour un coût par commande,
  journald ne datant qu'à la seconde), donc un épisode en soi : l'entrée de `docs/TODO.md` est
  **réécrite** avec ces chiffres et ses arbitrages (sortir un geste du chemin critique, changer
  le `Type=`, ou déplacer l'écriture des unités vers `pupisto.debian.sh`), au lieu de rester
  « cause inconnue ».

- **2026-09-03** — épisode 26 (`bin/scripts/marionnet-relay.00-journal.sh`,
  `uml/pupisto.debian/pupisto.debian.sh.files/marionnet-relay{,.trixie}`) : **le relais se date à
  la microseconde, et les ~7 s ont enfin des noms.** L'ép. 25 butait sur la granularité :
  journald ne date qu'à la **seconde**, pour un relais qui exécute 60 à 100 commandes tracées par
  seconde. Le remède tient en une définition de `PS4` portant **`$EPOCHREALTIME`** — le prompt
  étant imprimé **avant** la commande, l'écart entre deux lignes **est** le coût de celle du
  milieu. Rien à mesurer depuis l'hôte, rien à instrumenter à la main.
  **Deux endroits, et le premier ne suffisait pas** : poser `PS4` dans le prologue de journal
  déposé par Marionnet n'a daté que **6 lignes sur 325** — mesuré — parce que ce prologue n'est
  sourcé qu'à la **fin** du relais (phase de configuration), alors que l'essentiel de la trace
  (233 lignes) vient du `set -x` que le relais active lui-même sous `debug_mode`, **dans
  l'image**. Les deux sites reçoivent donc la même définition, avec la même garde :
  `$EPOCHREALTIME` est une variable de **bash ≥ 5.0**, et là où le shell est plus ancien
  (wheezy, bash 4.2) elle laisserait un champ vide — le choix se fait **une fois**, à la pose du
  `PS4`, pas par une expansion incapable de dire qu'elle a échoué.
  **Mesuré** (boot trixie, 314 lignes datées couvrant **4,55 s**) :
  **1,633 s** dans le bloc **non tracé** de `00-journal:311` — écriture des unités
  `marionnet-report`/`marionnet-watch`, **`systemctl daemon-reload`** (1,30 s à lui seul) et
  `systemctl start` ; **~1,02 s** en **huit** `systemctl stop getty@tty$i.service` lancés **un par
  un** (`marionnet-relay:415-417`, 0,085 à 0,144 s chacun) ; 0,135 s pour `ip netns add`, 0,086 s
  pour le `mount hostfs` ; le reste étant ~300 commandes à ~5 ms.
  **La mesure sans publier quoi que ce soit** : le relais vit dans l'image, donc le correctif du
  dépôt n'atteindra un invité qu'à la prochaine fabrication ; la mesure d'aujourd'hui a été prise
  en appliquant le **même** changement dans le **COW jetable** d'une machine (par `exec` d'un
  script déposé dans le hostfs), puis en la redémarrant — aucune image produite, aucune publiée.
  **Aucun correctif ici, et c'est délibéré** : les deux gros postes sont maintenant nommés et
  chiffrés dans `docs/TODO.md` avec leurs contreparties (grouper les gettys en **une** invocation
  ~0,9 s ; livrer les deux unités dans l'image supprimerait le `daemon-reload` mais leur
  `TimeoutStopSec` vient du hostfs du boot courant).

- **2026-09-03** — épisode 27 (`uml/pupisto.debian/pupisto.debian.sh.files/marionnet-relay.trixie`,
  `Makefile.d/filesystem.update-published-image.sh`, `docs/TODO.md`) : **les gettys en une seule
  invocation, et ce que la mesure a corrigé de l'attente.** Le premier des deux postes chiffrés
  par l'ép. 26 est traité : les unités surnuméraires (`stop`) comme les consoles demandées
  (`start`) sont réunies dans un tableau et passées à `systemctl` **d'un coup**, garde de tableau
  vide comprise (`console_no` > 8 ne doit pas produire une commande sans argument).
  **Le gain n'est pas celui qu'annonçait le TODO** : au boot, la ligne unique coûte **0,577 s**
  contre **~1,02 s** pour les huit, et l'A/B joué **dans le même invité, au même boot** (3 tours)
  donne **0,761 / 0,811 / 0,808 s** pour huit appels contre **0,485 / 0,516 / 0,486 s** pour un
  seul. Soit **~0,3 s**, pas ~0,9 : un `systemctl` de plus ne vaut que ~41 ms, et **les huit
  unités coûtent dans la même transaction** — ~0,50 s alors qu'**aucun getty ne tourne**
  (`NAutoVTs=0`). Ce que le modèle « un aller-retour au lieu de huit » ne disait pas est écrit
  dans `docs/TODO.md`, avec la suite possible (ne rien arrêter quand rien n'est chargé).
  **La preuve par l'outil de l'ép. 23**, et sans rien publier : l'image publiée
  `machine-debian-trixie-16341` reçoit le relais de HEAD par `--in-guest-script`, la variante est
  publiée **hors** du répertoire de release (`--no-tarball`, scratchpad) sous le nom
  `machine-debian-trixie-11950`, et c'est **elle** qu'on redémarre pour lire sa trace. Deux
  choses apprises en chemin, **à ne pas défaire** : (1) la trace du relais n'est **pas** dans
  `/mnt/hostfs/rc_config.log` — celui-ci ne porte que les 6 lignes du prologue (ép. 26), le reste
  étant la sortie d'erreur du service, donc `journalctl -u marionnet-relay` ; (2)
  **`--in-guest-script` n'avait jamais tourné** et mourait aussitôt : il cherchait le hostfs
  **sous `$PROJECT_DIR`**, où ne vit que le `.mar`, alors que le répertoire de travail est
  `<MARIONNET_TMPDIR>/marionnet-<aléa>.dir/<projet>/hostfs/<composant>` — l'aléa n'étant pas
  prédictible, l'outil **demande** désormais au canal, qui publie ce chemin dans le champ
  `hostfs` de `rc-get` (`bin/control_server.ml`, `Co_rc_read`). Une ligne de plus sur la socket,
  et rien à deviner.

## Constat entrant — trixie n'écrit pas `marionnet-guest-ready` (2026-08-15)

Relevé **hors de ce chantier**, par l'épisode 2 de `modernisation-world-bridge`, en pilotant une
session par le canal de contrôle : sur une machine `debian-trixie-47362` (noyau `6.12.95`),
`wait <machine> --ready` **expire au bout de 240 s** —

> `"m1" wrote no marionnet-guest-ready in its hostfs directory after 240.1s`

— alors que **l'invité est parfaitement vivant** : les `exec` qui suivent immédiatement répondent
tous en ~1,2 s (`ip link set`, `ip addr add`, `ping`, `nslookup`, tous `status:0`). Le marqueur de
disponibilité n'est donc pas écrit par le rootfs trixie, ou l'est ailleurs que là où le canal le
cherche.

Pourquoi cela appartient à ce chantier : le marqueur est posé par le **relais de démarrage**, et
c'est ici qu'a été construit le dispatch SysV/systemd (`marionnet-relay.trixie`, épisode 20). C'est
très probablement le même mécanisme que celui déjà mesuré à l'épisode 16 puis reversé au TODO
transverse pour le rapport : une unité systemd **démarrée depuis le relais** ne voit son job
exécuté qu'**en fin de boot**, bien après le moment où le marqueur devrait exister.

Conséquence pratique tant que ce n'est pas corrigé : **tout script qui attend `--ready` sur un
invité trixie attendra pour rien**, y compris les bancs de TP (`marionnet-lab-design`) et les
scripts d'exemple de `doc-src/scripting/`. Le contournement employé à l'épisode 2 est d'attendre
`--state=on` puis d'enchaîner directement sur les `exec`, qui fonctionnent.

## Constat entrant — `BINARY_LIST` polluée et dupliquée, par une redirection manquante (2026-08-23)

> **CLOS le 2026-08-23 par l'épisode 4 de `modernisation-installation-marionnet`** — corrigé
> là-bas et non ici, la faute étant dans `uml/pupisto.common/`, commune aux deux pupisto. Le
> diagnostic ci-dessous est exact et reste comme trace ; il lui manquait une date : `git log -L`
> montre que la redirection existait (`8b814aa`) et a été perdue en **2014** par `77fb25a`, en
> emballant le bloc `export -p` voisin dans un `{ … } >> $COOL_SUDO`. La réparation ne restaure
> **pas** la propagation à l'identique : `e` et `u` en sont retirés, parce que douze ans de
> fonctions appelées par `sudo_fcall` — `careful_chroot` et son démontage d'épilogue en tête —
> n'ont jamais tourné sous `errexit`. Détail : `docs/modernisation-installation-marionnet.md`.

Relevé **hors de ce chantier**, par l'épisode 3 de `modernisation-installation-marionnet`, en
publiant l'image trixie : le `.conf` de `machine-debian-trixie-47362` **installé** porte une
`BINARY_LIST` qui (a) commence par un `set -hxBE` qui n'est pas un binaire, (b) tient sur **deux
lignes**, et (c) **répète chaque entrée** (`7z 7z 7za 7za Crack Crack …`).

Deux causes distinctes, toutes deux dans la chaîne de fabrication des images :

**1. Une redirection manquante** — `uml/pupisto.common/toolkit_chroot.sh`, dans `sudo_fcall` :

```bash
 # Put all current set-options (-e, -x, ..):
 echo "set -$-";                    # <-- il manque  >> $COOL_SUDO
```

Toutes les autres lignes de la fabrication du script temporaire sont redirigées vers
`$COOL_SUDO` ; **celle-ci ne l'est pas**. Le défaut est donc double, et le second est le plus
grave parce qu'il est muet :
- la ligne part sur la **sortie standard** de `sudo_fcall`, donc dans toute capture — c'est ainsi
  que `BINARY_LIST=$(sudo_chroot_binary_list $DEBIANROOT)` (`pupisto.debian.sh:1514`) reçoit
  `set -hxBE` comme premier « binaire » ;
- les options du shell appelant (`-e`, `-x`…) **n'atteignent jamais** le script exécuté en root,
  qui tourne donc sans elles alors que le code croit les lui transmettre. Aucun message ne le
  signale.

Vaut pour **tout** appelant de `sudo_fcall` / `sudo_chroot_fcall` dont on capture la sortie, pas
seulement `binary_list`.

**2. Le doublon vient du `PATH`, pas de la capture** — `binary_list`
(`uml/pupisto.common/toolkit_chroot.sh:328`) balaie les répertoires du `PATH` et termine par
`sort` **sans `-u`**. Sur une Debian à `/usr` fusionné, le `PATH` contient à la fois `/bin` et
`/usr/bin` (le premier étant un lien vers le second) : chaque binaire est donc trouvé deux fois.
C'est neuf par rapport aux images d'avant la fusion — wheezy (2014) n'a pas le problème, sa
`BINARY_LIST` est propre et sur une seule ligne.

Pourquoi cela appartient à ce chantier : `uml/pupisto.*` est la chaîne qui **fabrique** les
images invitées, et l'image trixie en est le produit courant. Tant que ce n'est pas corrigé,
**chaque nouvelle image reconduira le défaut**.

Portée réelle, à ne pas surestimer : Marionnet ne lit `BINARY_LIST` que pour proposer la
complétion des binaires disponibles dans un invité (`bin/disk.ml:458`) ; une entrée fantôme et
des doublons dégradent cette liste, ils ne cassent rien. Le script de publication
(`Makefile.d/filesystem.prepare-snapshot-to-publish.sh`) **reconstruit** la liste par un montage
`loop,ro` de l'image produite, avec `sort -u` : les images **republiées** sortent donc assainies
(2 060 binaires, une ligne). Cela masque le défaut sans le corriger — la source, elle, le garde.
