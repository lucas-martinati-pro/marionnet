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
