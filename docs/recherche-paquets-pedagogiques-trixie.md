# Paquets pédagogiques pour l'image invitée Marionnet — Debian 13 « Trixie » amd64

Recherche menée via Tavily (recherche + extraction directe des fiches `packages.debian.org/trixie/…`)
le 2026-07-10, en vue du rafraîchissement de l'image invitée UML de Marionnet (chantier
`marionnet-kernel-rootfs`). Public visé : université / école d'ingénieurs, réseau > système >
cybersécurité > programmation (secondaire).

## 1. Synthèse

Le corpus de TP publics examinés (majoritairement des universités et IUT français : Paris 13,
Aix-Marseille, Artois/CRIL, UT-Capitole, Nice, plus quelques syllabus anglo-saxons) fait ressortir
un noyau très stable d'outils réseau : **nmap, Wireshark/tcpdump/tshark, netcat, iptables/nftables,
bind9, isc-dhcp-server, traceroute, OpenVPN** reviennent systématiquement. Côté sécurité, le
sous-ensemble « pédagogique » de Kali/Parrot est net : **nmap, Wireshark, tcpdump, Scapy** sont
omniprésents ; **hydra, nikto, sqlmap, aircrack-ng** apparaissent dans des TP encadrés (brute-force,
scan web, injection SQL, Wi-Fi) ; **Metasploit** est utilisé mais quasi toujours contre une cible
volontairement vulnérable (Metasploitable2) et n'est **pas packagé dans Debian** (dépôt tiers
Rapid7) ; **Burp Suite** est très présent en sécurité web mais est **propriétaire** (licences de
formation PortSwigger). Deux arbitrages libres vs non-libres se dégagent nettement : (1) Metasploit
et Burp Suite doivent être écartés d'une image « Debian main only » — aucun équivalent libre
strictement à parité n'est packagé nativement (OWASP ZAP est la piste à vérifier) ; (2) VSCodium,
bien que **libre** (MIT), **n'est pas packagé dans Debian** (issue GitHub confirmant l'absence,
faute de mainteneur) — donc même en acceptant un éditeur non-Kali, il faudrait un dépôt tiers, ce
qui contredit la contrainte « main ». Deux dépréciations méritent d'être signalées explicitement à
l'utilisateur : **isc-dhcp-server est marqué « (deprecated) » par Debian/ISC** (EOL au profit de
Kea) tout en restant le logiciel documenté dans la quasi-totalité des TP DHCP trouvés ; et
**Quagga** (utilisé dans un TP de routage trouvé) est vraisemblablement obsolète au profit de
**FRR**, activement packagé et maintenu en trixie. Enfin, `nftables` remplace officiellement
`iptables`/`ip6tables`/`arptables`/`ebtables` dans la description Debian elle-même, mais les TP
observés utilisent presque tous encore la syntaxe `iptables` — les deux paquets coexistent en
trixie et peuvent être installés ensemble sans conflit pédagogique.

## 2. Tableaux par matière

Légende « libre ? / section » : L = logiciel libre (FSF/GNU au sens large) ; NL = non-libre ;
« main » = section Debian `main` (le reste hors périmètre voulu par l'utilisateur).

### 2.1 Réseau

| paquet Debian (trixie/main) | rôle | justification pédagogique | libre ? / section | source(s) |
|---|---|---|---|---|
| `iproute2` | `ip`, `ss`, `tc` — config réseau moderne | remplace `ifconfig`/`route`, socle de tout TP réseau Linux | L / main (confirmé, 6.15.0-1) | packages.debian.org/trixie/iproute2 |
| `tcpdump` | capture CLI | omniprésent dans les TP d'analyse de trafic (Paris13, CRIL) | L / main (confirmé, 4.99.5-2) | packages.debian.org/trixie/tcpdump ; lipn.univ-paris13.fr/~loddo/…/tp-marionnet-7.pdf |
| `wireshark` | analyseur graphique (Qt) | outil pédagogique n°1 pour les couches réseau | L / main (confirmé, 4.4.15-0+deb13u1) | packages.debian.org/trixie/wireshark |
| `tshark` | version console de Wireshark | utile en VM légère / scripts, complète tcpdump | L / main (confirmé, 4.4.15) | packages.debian.org/trixie/tshark |
| `nmap` | scan de ports/hosts | outil le plus cité dans les TP réseau et sécurité (labs dédiés) | L / main (quasi-certain — cité par packages.debian.org/stable/nmap, page trixie non re-vérifiée individuellement cette session) | cs.colostate.edu/~ct320 Nmap lab ; app.wku.edu CIT484 syllabus ; packages.debian.org/stable/nmap |
| `traceroute` | traçage de route | TP de diagnostic réseau classique | L / main (confirmé, 1:2.1.6-1) | packages.debian.org/trixie/traceroute ; tvaira.free.fr/reseaux/tp12-traceroute_Internet.pdf |
| `mtr` ou `mtr-tiny` | traceroute+ping combinés | complète traceroute ; `mtr-tiny` = variante CLI sans dépendances GTK/X11, plus légère pour UML | L / main (confirmé, 0.95-1.1 ; `mtr-tiny` non vérifié séparément) | packages.debian.org/trixie/mtr |
| `netcat-openbsd` | couteau suisse TCP/UDP | très utilisé en TP (démonstration de flux, transfert brut) | L / main (confirmé, 1.229-1) | packages.debian.org/trixie/netcat-openbsd ; cril.univ-artois.fr tp4Reseaux.pdf |
| `socat` | relais bidirectionnel avancé | complément moderne à netcat pour TP plus poussés | L / main (confirmé, 1.8.0.3-1) | packages.debian.org/trixie/socat |
| `iperf3` | mesure de débit | TP de performance réseau | L / main (confirmé, 3.18-2+deb13u2) | packages.debian.org/trixie/iperf3 |
| `bind9` + `bind9-dnsutils` | serveur DNS + `dig`/`nslookup`/`nsupdate` | TP DNS classique (zones, résolution) ; `dnsutils` a été renommé `bind9-dnsutils` | L / main (confirmé, 1:9.20.23-1~deb13u1) | packages.debian.org/trixie/bind9 ; packages.debian.org/trixie/bind9-dnsutils ; TP-dns (scribd) |
| `kea` | serveur DHCP moderne (ISC) | successeur recommandé d'isc-dhcp (cf. § écarter) | L / main (confirmé, 2.6.3-1, métapaquet) | packages.debian.org/trixie/kea |
| `isc-dhcp-server` | serveur DHCP historique | **déprécié** par l'amont mais massivement documenté dans les TP trouvés (chemins `/etc/dhcp/dhcpd.conf` cités) — cf. § écarter | L / main (confirmé présent, 4.4.3-P1-8, étiqueté « deprecated ») | packages.debian.org/trixie/isc-dhcp-server ; www-lipn.univ-paris13.fr/~evangelista/cours/R203/R203-tp.pdf |
| `nftables` | pare-feu moderne (remplace iptables) | description Debian : remplace iptables/ip6tables/arptables/ebtables | L / main (confirmé, 1.1.3-1) | packages.debian.org/trixie/nftables |
| `iptables` | pare-feu historique, syntaxe très documentée | quasi tous les TP pare-feu/NAT trouvés utilisent cette syntaxe (UT-Capitole, Paris13) | L / main (à vérifier — non re-fetché individuellement cette session, présence quasi certaine) | dsi.ut-capitole.fr/cours/TP_iptables.pdf ; lipn.univ-paris13.fr tp-marionnet-7.pdf |
| `frr` | suite de routage moderne (BGP/OSPF/RIP/IS-IS…) | successeur activement maintenu de Quagga (cf. § écarter) | L / main (confirmé, 10.3-3+deb13u1) | packages.debian.org/trixie/frr |
| `openssh-server` / `openssh-client` | SSH | omniprésent (accès distant, tunnels) | L / main (confirmé) | packages.debian.org/trixie/openssh-server |
| `rsync` | synchronisation de fichiers | classique en admin système/réseau | L / main (à vérifier — non re-fetché cette session, paquet historique quasi certain) | connaissance générale, non re-vérifié individuellement |
| `tmux` | multiplexeur de terminal | utile en TP à session distante (survit à une déconnexion SSH) | L / main (à vérifier, idem) | idem |
| `curl` / `wget` | clients HTTP CLI | outils de base, tests HTTP en TP réseau/sécu | L / main (à vérifier, idem) | idem |

### 2.2 Système

| paquet Debian (trixie/main) | rôle | justification pédagogique | libre ? / section | source(s) |
|---|---|---|---|---|
| `htop` | supervision interactive des processus | remplace `top`, très utilisé en TP admin système | L / main (à vérifier, non re-fetché cette session) | connaissance générale |
| `lsof` | fichiers ouverts par processus | TP diagnostic système ; confirmé indirectement comme dépendance de `frr` | L / main (confirmé indirectement — dépendance listée sur la fiche `frr`) | packages.debian.org/trixie/frr (liste des dépendances) |
| `sysstat` | `sar`, `iostat`, `mpstat`… | TP de supervision de charge système | L / main (à vérifier) | connaissance générale |
| `strace` | trace d'appels système | classique en TP « comprendre ce que fait un programme » | L / main (à vérifier) | connaissance générale |
| `ltrace` | trace d'appels de bibliothèque | complète strace — **attention** : a connu des périodes de retrait de Debian testing par le passé faute de mainteneur actif ; à tester explicitement avant d'en dépendre | L / main (à vérifier plus spécifiquement que les autres — risque de statut instable) | connaissance générale, non confirmé pour trixie cette session |
| `bash` | shell / scripting | base de tout TP système | L / main (paquet essentiel, quasi certain) | connaissance générale |

### 2.3 Cybersécurité (transversal)

| paquet Debian (trixie/main) | rôle | justification pédagogique | libre ? / section | source(s) |
|---|---|---|---|---|
| `nmap` | scan/découverte | voir tableau réseau — usage double réseau/sécurité | L / main (quasi-certain) | voir § 2.1 |
| `wireshark` / `tcpdump` / `tshark` | analyse de trafic | voir tableau réseau | L / main (confirmé) | voir § 2.1 |
| `python3-scapy` | forge/sniff de paquets programmable | TP avancés (construction de paquets, tests actifs) ; complète tcpdump/Wireshark | L / main (présence Debian confirmée en sid par la recherche ; trixie quasi-certain, non re-fetché individuellement) | packages.debian.org/sid/python3-scapy ; repo.zenk-security.com « Scapy en pratique » |
| `aircrack-ng` | suite Wi-Fi (WEP/WPA) | TP Wi-Fi — **nécessite une carte en mode monitor, absente d'une VM UML** : usage limité au traitement de captures pré-enregistrées | L / main (**confirmé trixie**, 1:1.7+git20230807.4bf83f1a-2) | packages.debian.org/stable/allpackages (recherche « aircrack-ng ») |
| `hydra` | brute-force d'authentification (FTP/SSH/HTTP…) | TP « faiblesse d'authentification » sur cibles contrôlées | L / main (à vérifier trixie — page individuelle non chargée cette session ; présente en sid selon la recherche, licence possiblement AGPLv3 selon la fiche Kali, à confirmer) | packages.debian.org/sid/net/hydra (cité par la recherche) ; kali.org/tools/hydra |
| `john` (John the Ripper) | craquage de mots de passe (dictionnaire) | TP classique de renforcement de mots de passe | L / main (à vérifier trixie — non confirmé directement, présence historique dans Debian très probable) | openwall.com/john ; kali.org/tools/john |
| `nikto` | scanner de vulnérabilités web basique | TP sécurité web (détection simple) | L / main (confirmé en **bookworm** ; trixie très probable mais non re-vérifié) | packages.debian.org/bookworm/net/nikto |
| `sqlmap` | automatisation d'injection SQL | TP injection SQL, largement documenté | L (GPLv2, **note** : double licence GPL/commerciale évoquée par le projet — à clarifier laquelle est packagée) / main (à vérifier trixie) | sqlmap.org ; github.com/sqlmapproject/sqlmap |
| `hashcat` | craquage de hash accéléré | démonstration crypto/mots de passe — **peu pertinent sans GPU** (UML n'a pas d'accès GPU réel), utile seulement en mode CPU réduit | L (MIT) / main (à vérifier — aucune page Debian trouvée dans cette recherche) | hashcat.net |
| `gnupg` | chiffrement/signature GPG | TP crypto appliquée classique | L / main (paquet de base, quasi certain) | perso.limos.fr TP2-Crypto-web.pdf |
| `openssl` | boîte à outils crypto/TLS | TP crypto/TLS en ligne de commande | L (Apache-2.0 depuis OpenSSL 3) / main (quasi certain) | wiki.pminfo.fr/openssl |
| `sleuthkit` | forensic disque (CLI) | TP d'introduction au forensic | L / main (confirmé en sid par la recherche ; trixie très probable) | packages.debian.org/sid/sleuthkit ; github.com/sleuthkit/sleuthkit |
| `binwalk` | analyse/extraction de firmware | TP reverse/firmware | L (à vérifier) / main (à vérifier — non confirmé dans cette recherche) | usages tutoriels cités, page Debian non trouvée |

### 2.4 Programmation (secondaire — toolchains + éditeurs)

| paquet Debian (trixie/main) | rôle | justification pédagogique | libre ? / section | source(s) |
|---|---|---|---|---|
| `gcc`, `g++`, `make`, `gdb` | toolchain C/C++ | TP de programmation système classiques | L / main (paquets de base, quasi certains) | connaissance générale, non re-vérifiés individuellement |
| `rustc`, `cargo` | toolchain Rust | langage mainstream demandé ; Debian packagé (version potentiellement en retard sur `rustup`, acceptable en environnement sans Internet) | L / main (à vérifier) | connaissance générale |
| `python3`, `python3-pip`, `python3-venv`, `ipython3` | toolchain Python | langage mainstream demandé | L / main (paquets de base, quasi certains) | connaissance générale |
| `bash` | scripting | déjà listé en § système | L / main | — |
| `vim` (ou `vim-nox`) | éditeur texte confortable | demande explicite : éditeur texte, pas d'IDE | L / main (quasi certain) | Boston University TechWeb (comparatif d'éditeurs, générique) |
| `neovim` | alternative moderne à vim | même usage, plus moderne (LSP intégrable si besoin ultérieur) | L / main (à vérifier) | idem |
| `nano` | éditeur texte simple pour débutants | recommandé pour étudiants non familiers de vim | L / main (paquet de base, quasi certain) | idem |
| `emacs` (ou `emacs-nox`) | éditeur texte avancé | déjà cité dans les stacks « expert » de l'utilisateur | L / main (quasi certain) | idem |
| `kate` | éditeur graphique léger (KDE) | demande explicite : un éditeur graphique léger, pas un IDE | L / main (quasi certain) | idem |
| `geany` | IDE-éditeur très léger, multi-langage | alternative légère à Kate, faible empreinte | L / main (quasi certain) | geany.org (« Flyweight IDE ») |
| `gedit` | éditeur graphique GNOME | **confirmé présent en trixie** (`gedit` 48.1-4, `gedit-dev` listé) — alternative graphique simple | L / main (**confirmé**) | packages.debian.org/stable/devel (liste `gedit-dev`) |
| `mousepad` | éditeur graphique XFCE, très léger | alternative encore plus légère si environnement XFCE utilisé | L / main (à vérifier) | connaissance générale |

## 3. À écarter / attention

| Outil | Problème | Alternative recommandée |
|---|---|---|
| **Metasploit Framework** | **Absent de Debian** (aucun `metasploit-framework` dans les dépôts par défaut) ; nécessite le dépôt tiers Rapid7 (`apt.metasploit.com`, hors main) ; licence globale du framework mixte (BSD-3 mais certains modules non-libres/restrictifs) | Pas d'équivalent packagé strict ; si le TP l'exige vraiment, l'installer explicitement hors « main » en le signalant comme exception assumée. À défaut, construire des scénarios d'exploitation pédagogique avec des scripts Python/Scapy maison sur des cibles jouets (moins clé-en-main mais 100 % main). |
| **Burp Suite** | **Propriétaire** (PortSwigger) ; le mode « éducation » repose sur des licences temporaires, pas sur un paquet libre | **OWASP ZAP** (Apache-2.0) — piste à vérifier : paquet Debian `zaproxy` — statut trixie **non confirmé dans cette recherche**, à tester avant adoption |
| **VS Code (binaire Microsoft)** | Non-libre (licence Microsoft, télémétrie) | **VSCodium** est libre (MIT) **mais absent de Debian** (confirmé : demande de paquetage fermée « not planned » faute de mainteneur, nécessite un dépôt tiers) → **ni l'un ni l'autre ne respecte la contrainte « main »** ; rester sur `kate`/`geany`/`gedit`/`mousepad`, cohérent avec la demande initiale d'éditeur léger sans IDE |
| **isc-dhcp-server** | Marqué explicitement **« (deprecated) »** sur sa propre fiche Debian ; ISC a arrêté le projet au profit de Kea (billet cité par Debian lui-même) | **Kea** (`kea`, confirmé main trixie) pour tout nouveau matériel pédagogique ; garder isc-dhcp-server en option de compatibilité vu le volume de TP existants qui l'utilisent — décision à trancher par l'auteur, pas neutre techniquement |
| **Quagga** | Cité dans un TP trouvé mais **probablement obsolète/absent** de trixie (non revérifié directement, mais Debian a progressivement retiré Quagga au profit de FRR dans les cycles récents) | **FRR** (`frr`, confirmé main trixie, activement maintenu) |
| **aircrack-ng en VM UML** | Le paquet est libre et présent (confirmé), mais **son usage réel (capture Wi-Fi live, mode monitor) est impossible sans carte Wi-Fi réelle** dans une VM UML | Conserver le paquet pour le **traitement de captures `.cap` pré-fournies** (craquage offline pédagogique), pas pour la capture live |
| **hashcat** | Accélération GPU inexistante en UML (pas de GPU réel) ; en CPU seul, très lent, valeur pédagogique réduite | Garder `john` pour les démonstrations de craquage CPU, réserver hashcat à un TP hors-VM si un poste avec GPU est disponible |
| **ltrace** | Historique de retraits de Debian testing par manque de mainteneur — statut à re-tester spécifiquement avant de bâtir un TP dessus | `strace` seul est plus sûr à moyen terme si `ltrace` s'avère absent |

## 4. Zones d'incertitude (à confirmer avant intégration définitive)

- **Statut trixie individuel non re-vérifié cette session** (forte présomption de présence en main,
  mais pas de fiche `packages.debian.org/trixie/…` rechargée avec succès) : `nmap`, `iptables`,
  `rsync`, `tmux`, `curl`, `wget`, `htop`, `sysstat`, `strace`, `ltrace`, `gcc`/`g++`/`make`/`gdb`,
  `rustc`/`cargo`, `python3`/`pip`/`venv`/`ipython3`, `vim`/`neovim`/`nano`/`emacs`, `mousepad`,
  `hydra`, `john`, `nikto` (confirmé seulement en bookworm), `sqlmap`, `binwalk`. La méthode
  d'extraction Tavily a été instable sur les gros lots d'URL (succès partiel et non déterministe) ;
  un simple `apt-cache policy <paquet>` sur une image trixie réelle lèvera le doute en quelques
  secondes, plus fiable que d'insister côté recherche web.
- **Licence exacte de `hydra`** : la fiche Kali évoque AGPL-3.0 pour une version, à confirmer contre
  le `copyright` du paquet Debian réel (`/usr/share/doc/hydra/copyright`) plutôt que sur une source
  tierce.
- **`sqlmap`** : double licence GPLv2 + « commerciale » mentionnée sur le site amont — à clarifier
  si la variante packagée Debian est purement GPLv2 (attendu) ou si des composants optionnels non
  libres existent.
- **`zaproxy` (OWASP ZAP)** : alternative libre suggérée à Burp Suite, mais son paquetage effectif
  dans Debian trixie/main n'a **pas** été vérifié dans cette recherche — à tester avant de le
  proposer comme remplacement ferme.
- **Quagga** : absence supposée de trixie par déduction (non testée directement) — à confirmer par
  `apt-cache policy quagga` avant d'affirmer son retrait.
- **Poids réel de `wireshark` (Qt6 complet) dans une VM UML aux ressources modestes** : le paquet
  `wireshark` tire toute la pile Qt6 ; si l'empreinte disque/mémoire est un souci, `tshark` seul
  (déjà listé, dépendances bien plus légères) peut suffire pour l'essentiel des TP CLI, en gardant
  `wireshark` optionnel pour les séances où l'interface graphique apporte une vraie valeur
  pédagogique.

## 5. Bibliographie

### TP et syllabus (usage pédagogique attesté)
- https://github.com/tecnico-sec/Traffic-Analysis
- https://fr.scribd.com/document/912144172/Laboratoire-4-Analyse-avec-NMAP
- https://lipn.univ-paris13.fr/~loddo/files/COURS-TCPIP/tp-marionnet-7.pdf
- https://lipn.univ-paris13.fr/~kanawati/M4210/M4210-TP1.pdf
- https://www-lipn.univ-paris13.fr/~evangelista/cours/R316-CYBER/R316-CYBER-tp-correction.pdf
- https://cril.univ-artois.fr/~lecoutre/teaching/reseaux/tp4Reseaux.pdf
- https://www-lipn.univ-paris13.fr/~loddo/files/COURS-TCPIP/tp-marionnet-5.pdf
- https://www-lipn.univ-paris13.fr/~evangelista/cours/R203/R203-tp.pdf
- https://dsi.ut-capitole.fr/cours/TP_iptables.pdf
- https://lipn.univ-paris13.fr/~petrucci/polycopies/TP_M2103.pdf
- https://arnaud-fevrier.pedaweb.univ-amu.fr/MR/Le-serveur-OpenVPN.html
- https://tvaira.free.fr/reseaux/tp12-traceroute_Internet.pdf
- https://i3s.unice.fr/~deneire/cours/courses/TP5-ARP-Ethernet.pdf
- https://fr.scribd.com/document/842320067/TP-dns
- https://cs.colostate.edu/~ct320/Fall19/Lab/Nmap
- https://app.wku.edu/syllabus/get?file=202210_prod_CIT484700_202210_41251.pdf
- https://fengweiz.github.io/17sp-csc4992/labs/lab1-Instruction.pdf
- https://fengweiz.github.io/17sp-csc4992/labs/lab4-instruction.pdf
- https://fr.scribd.com/document/866237684/TP-02-En-Francais-reseaux
- https://scribd.com/document/984608845/Web-Application-Attack-Simulation-Hydra-Based-Brute-Force-Analysis
- https://fr.scribd.com/document/715701257/12-Nikto-5SOA
- https://fr.scribd.com/document/680570279/03-TP-03-SQL-Injection
- https://perso.limos.fr/~palafour/SECWEB/2023-TP2-Crypto-web.pdf
- https://wiki.pminfo.fr/fr/cryptographie/openssl
- https://repo.zenk-security.com/Techniques%20d.attaques%20%20.%20%20Failles/Scapy%20en%20pratique.pdf
- https://dissec.to/scapycon-automotive-2025

### Outils sécurité (documentation amont)
- https://aircrack-ng.org/doku.php?id=fr%3Aaircrack-ng
- https://doc.ubuntu-fr.org/aircrack-ng
- https://github.com/aircrack-ng/aircrack-ng
- https://openwall.com/john
- https://kali.org/tools/john
- https://sqlmap.org
- https://github.com/sqlmapproject/sqlmap
- https://hashcat.net/hashcat
- https://portswigger.net/support/burp-suite-training-faqs
- https://portswigger.net/burp/documentation/desktop/getting-started
- https://github.com/sleuthkit/sleuthkit
- https://sleuthkit.org
- https://thunderysteak.github.io/tl-wa901nd-basic-re (usage pédagogique binwalk)

### Metasploit / VSCodium (absence de Debian, confirmée)
- https://linuxcapable.com/how-to-install-metasploit-on-debian-linux
- https://github.com/rapid7/metasploit-framework/issues/19074
- https://snapcraft.io/install/metasploit-framework/debian
- https://linuxcapable.com/install-vscodium-on-debian-linux
- https://vscodium.com
- https://github.com/VSCodium/vscodium/issues/456

### Fiches Debian trixie consultées directement (packages.debian.org)
- https://packages.debian.org/trixie/iproute2
- https://packages.debian.org/trixie/tcpdump
- https://packages.debian.org/trixie/wireshark
- https://packages.debian.org/trixie/tshark
- https://packages.debian.org/trixie/traceroute
- https://packages.debian.org/trixie/mtr
- https://packages.debian.org/trixie/netcat-openbsd
- https://packages.debian.org/trixie/socat
- https://packages.debian.org/trixie/iperf3
- https://packages.debian.org/trixie/bind9
- https://packages.debian.org/trixie/bind9-dnsutils
- https://packages.debian.org/trixie/isc-dhcp-server
- https://packages.debian.org/trixie/kea
- https://packages.debian.org/trixie/nftables
- https://packages.debian.org/trixie/frr
- https://packages.debian.org/trixie/openssh-server
- https://packages.debian.org/stable/nmap (cité par la recherche, non re-fetché directement)
- https://packages.debian.org/bullseye/tcpdump (cité par la recherche)
- https://packages.debian.org/bookworm/net/nikto (cité par la recherche)
- https://packages.debian.org/sid/net/hydra (cité par la recherche)
- https://packages.debian.org/sid/python3-scapy (cité par la recherche)
- https://packages.debian.org/sid/sleuthkit (cité par la recherche)
- https://packages.debian.org/stable/allpackages (confirmation directe `aircrack-ng`, `gedit-dev`)
- https://packages.debian.org/stable/devel (confirmation directe `gedit-dev`)
