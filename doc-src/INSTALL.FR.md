# Installer Marionnet

> **Traduction française de `INSTALL.md`.** L'original anglais fait foi : en cas de divergence,
> c'est lui qu'il faut corriger, et cette page à sa suite.

*Quelle méthode utiliser, ce que chacune installe sur le système de fichiers, et ce que vous devez
ou pouvez faire ensuite.*

Marionnet est publié sous **trois formes prêtes à l'emploi**, toutes alimentées par le même
répertoire de release sur `www.marionnet.org` et portant toutes le **même binaire**. Celle qu'il
faut prendre dépend du gestionnaire de paquets de votre machine, pas de ce que vous comptez faire
de Marionnet :

| Votre machine | Prenez | § |
|---|---|---|
| Debian, Ubuntu et dérivées | le **dépôt apt** | § 2 |
| Fedora, famille RHEL (Rocky, AlmaLinux), openSUSE | le **dépôt dnf/zypper** | § 3 |
| tout le reste — ou vous ne voulez aucun gestionnaire de paquets | le **tarball précompilé** | § 4 |
| vous comptez modifier Marionnet | **depuis les sources** | § 6 |

Quelle que soit la méthode, les **images invitées et les noyaux UML se récupèrent séparément**
(§ 5) : ils pèsent des gibioctets et changent à leur propre rythme. Marionnet démarre sans eux et
le dit.

Marionnet est un programme graphique : il lui faut un affichage X (`DISPLAY`), et il en ouvre
l'accès aux invités avec `xhost` (§ 7.2).

Tout chemin relatif de cette page est relatif **au répertoire où se trouve ce fichier** :
`doc-src/` dans les sources, `<prefix>/share/doc/marionnet/` sur une machine où Marionnet est
installé.

## 1. Avant toute chose, sur une Debian ou une Ubuntu minimale

Les trois méthodes atteignent le site en **https**, et un système Debian ou Ubuntu *minimal* —
notamment une image de conteneur nue — ne porte **aucun magasin de certificats** (mesuré sur
Debian 12 et 13 et sur Ubuntu 24.04 et 26.04 ; les images de la famille RPM, elles, en ont un).
Sans lui, `apt` ne lira pas notre dépôt et l'installeur ne lira pas le catalogue, alors même que
le serveur est parfaitement debout :

```bash
sudo apt update && sudo apt install ca-certificates curl
```

`curl` est dans cette ligne pour la même raison : une image *slim* n'a pas non plus de
téléchargeur, et le § 2 récupère la clef de l'archive avec (`wget -O` à la place de `curl -o`
fait tout aussi bien).

`marionnet-install.sh` **nomme** cette cause plutôt que d'accuser le réseau, mais il ne peut pas
la réparer : installer ce paquet demande le gestionnaire de paquets en état de marche qui est
précisément en jeu.

## 2. Debian et Ubuntu — le dépôt apt

Mesuré sur **Debian 12, Debian 13, Ubuntu 24.04 et Ubuntu 26.04**.

```bash
sudo install -d /etc/apt/keyrings
sudo curl -o /etc/apt/keyrings/marionnet.asc \
     https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc
echo 'deb [signed-by=/etc/apt/keyrings/marionnet.asc] https://www.marionnet.org/download/apt/ ./' \
  | sudo tee /etc/apt/sources.list.d/marionnet.list
sudo apt update
sudo apt install marionnet
```

`download/apt` est un **point d'entrée stable** : il suit la série de publication courante, si
bien que la ligne ci-dessus n'a pas à être modifiée quand la série change.

### La clef

Le fichier `Release` du dépôt est signé, et c'est `signed-by=` qui fait qu'apt le vérifie. La
clef est :

```
Marionnet Archive Signing Key <loddo@lipn.univ-paris13.fr>
4A65 3434 0BF9 7733 E74C  9DFC 12E4 6000 225F 0E56
```

Elle vient de `git.launchpad.net`, et **non** de `www.marionnet.org` : c'est tout l'intérêt.
https ne prouve que ceci, que le serveur n'a pas été usurpé ; qui contrôle ce serveur réécrit les
paquets *et* les empreintes qui en répondent. Une signature déplace le point de confiance vers
une clef privée qui n'y vit pas.

*Ce qu'elle protège* : les machines **déjà installées**. Elles ne relisent jamais cette page — à
chaque `apt upgrade` elles contrôlent contre la clef présente sur leur propre disque, si bien que
personne qui prendrait le serveur demain ne peut leur pousser une mise à jour piégée, sur des
machines où Marionnet installe une règle sudoers. *Ce qu'elle ne protège pas* : votre toute
première installation, si vous apprenez tout d'une page compromise, qui nommerait une autre clef
et vérifierait parfaitement. La sortie est de comparer l'empreinte ci-dessus avec **une source
qui n'est pas cette page** : le dépôt git (§ *Où aller ensuite*), un polycopié imprimé, une
machine où Marionnet tourne déjà. Dans une salle de TP, l'empreinte lue à voix haute une fois en
début de semestre règle la question pour tout le monde.

**Contrôlez ce que vous avez récupéré — cette étape n'est pas facultative.** Mesuré :
`git.launchpad.net` répond `200` la plupart du temps et, environ une requête sur six, un `302`
vers sa page de connexion OpenID, et `curl` écrit dans le fichier ce qui lui est revenu.
N'ajoutez **pas** `-L` : cela suit la redirection et écrit la *page de connexion* — un échec qui
ressemble à une réussite.

```bash
sudo apt install gnupg
gpg --show-keys /etc/apt/keyrings/marionnet.asc     # doit afficher l'empreinte ci-dessus
```

Si autre chose s'affiche — ou rien — récupérez-la de nouveau. apt n'a pas besoin de `gnupg` pour
vérifier le dépôt (il a son propre vérificateur) ; vous en avez besoin, vous, pour *lire* ce que
vous avez récupéré.

### Les paquets

`apt install marionnet` installe l'application **et le noyau 64 bits** : `marionnet-kernels` est
un `Recommends:`, qu'apt installe par défaut — sans noyau, rien ne démarre du tout.
(`--no-install-recommends` est là pour qui n'en veut pas.) Les **images**, elles, restent des
`Suggests:` : des gibioctets sont un choix, pas une implication. Au § 3, `dnf install marionnet`
n'apporte que l'application, et c'est **mesuré, pas négligé** : dnf saute en silence la dépendance
faible sur le noyau (qui tire `glibc.i686`), donc ce canal la laisse en `Suggests:` et le dit
après l'installation. Dans les deux cas, le message d'après-installation **mesure** ce qui manque
encore et le nomme.

Ce ne sont pas des accessoires : **sans image, l'application ne démarre rien.** Un invité a
besoin d'un système de fichiers *et* d'un noyau que ce système de fichiers déclare supporter, et
Marionnet **ne propose pas** un système de fichiers dont aucun noyau supporté n'est installé.
Rien n'échoue et rien n'est dit : le composant est simplement absent de la liste.

| Paquet | Ce qu'il porte — et ce qui manque sans lui |
|---|---|
| `marionnet-kernels` | le noyau UML 64 bits `linux-6.12.95`. Sans lui, **les images récentes** (Debian trixie) ne sont pas proposées |
| `marionnet-fs-guignol` | la petite image invitée, machine *et* **routeur** — le seul système de fichiers de routeur publié. Sans lui, **aucun routeur ne peut être construit** |
| `marionnet-kernels-i386` | le noyau UML 32 bits `linux-6.12.95-i386`. Sans lui, **guignol et wheezy** ne sont pas proposés, et avec eux tout projet `.mar` antérieur à 2026 |

**Un routeur coûte deux paquets, pas un.** Mesuré dans le `.conf` publié : guignol déclare
`SUPPORTED_KERNELS='/3.2.[6-9]/ /-i386$/'`, que `linux-6.12.95` ne satisfait pas. Donc
`marionnet-fs-guignol` exige `marionnet-kernels-i386` — le noyau 64 bits ne le fera pas tourner —
et l'architecture étrangère ci-dessous n'est pas affaire de vieux projets seulement : c'est ce
que coûte un routeur aujourd'hui.

`marionnet-kernels-i386` exige une **architecture étrangère activée sur votre machine**, parce
que l'interpréteur du noyau 32 bits est `/lib/ld-linux.so.2` et que seul `libc6:i386` possède ce
chemin :

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install marionnet-kernels-i386
```

Sans cela, apt refuse le paquet en nommant `libc6:i386`. Activer une architecture étrangère est
une décision : c'est pourquoi le noyau 32 bits est un paquet à part.

**Si un tarball Marionnet (§ 4) a d'abord été installé sur cette machine**,
`/etc/marionnet/marionnet.conf` existe déjà et dpkg demandera quoi en faire — et un
`apt install` *non interactif* **échoue** là, parce que `DEBIAN_FRONTEND=noninteractive`
gouverne *debconf*, et non l'invite de conffile de dpkg. Pour garder la configuration que vous
avez déjà :

```bash
sudo apt install -o Dpkg::Options::=--force-confold marionnet
```

La version du fichier livrée par le paquet est alors laissée à côté, sous le nom
`marionnet.conf.dpkg-dist`. Les deux divergent sur un point qui compte : un paquet installe sous
`/usr`, un tarball sous `/usr/local`.

## 3. Fedora, famille RHEL et openSUSE — le dépôt dnf/zypper

Mesuré sur **Fedora 42, Rocky Linux 10, AlmaLinux 10 et openSUSE Leap 16**.

```bash
# 1. la clef — récupérée, REGARDÉE, et alors seulement importée
sudo install -d /etc/pki/rpm-gpg
sudo curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet \
     https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc
gpg --show-keys /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet   # doit afficher l'empreinte du § 2
sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet

# 2. le dépôt, puis l'application
sudo curl -o /etc/yum.repos.d/marionnet.repo \
     https://www.marionnet.org/download/rpm/marionnet.repo
sudo dnf install marionnet          # zypper install marionnet, sur openSUSE
```

`download/rpm` est le point d'entrée stable, comme `download/apt` l'est pour le § 2.

### La clef, de ce côté-ci

Même clef, même endroit, mêmes réserves qu'au § 2 — y compris la redirection une requête sur six.
La ligne du milieu du bloc ci-dessus vient **avant** `rpm --import` à dessein : importer *est*
l'acte de faire confiance, donc regarder ensuite serait regarder trop tard. Si `gpg` manque :
`sudo dnf install gnupg2` (`zypper install gpg2` sur openSUSE) ; ni `dnf` ni `rpm` n'en ont
besoin.

Ce qui diffère, c'est la *forme* de la vérification, pas sa force. Là où apt a une signature sur
`Release` qui couvre tous les paquets par leur empreinte, rpm a **deux** mécanismes, et la
strophe demande les deux :

| Réglage | Ce qu'il vérifie |
|---|---|
| `gpgcheck=1` | **chaque paquet**, par une signature que `rpmsign` a logée dans le fichier lui-même |
| `repo_gpgcheck=1` | **l'index**, par le `repodata/repomd.xml.asc` posé à côté |

La strophe nomme la clef par un **fichier local** (`gpgkey=file:///etc/pki/rpm-gpg/…`) et non par
une URL — d'où le fait que vous la récupériez vous-même ci-dessus : `dnf` récupère `gpgkey=`
lui-même et *suit les redirections*, sans qu'on puisse l'en empêcher, si bien qu'une URL pointant
sur `git.launchpad.net` télécharge la page de connexion une fois sur six et fait mourir
l'installation sur `Failed to import OpenPGP keys`, après avoir téléchargé tous les paquets.

`dnf` peut encore vous montrer une empreinte et vous demander s'il faut accepter la clef : il
tient un trousseau à lui pour `repo_gpgcheck`, que le `rpm --import` n'alimente pas. Comparez ce
qu'il affiche avec l'empreinte du § 2 avant de répondre oui.

**Sur la famille RHEL, activez d'abord EPEL** : `gtksourceview3`, l'une des dépendances
d'exécution de Marionnet, y vit et non dans les dépôts de base.

```bash
sudo dnf install epel-release
```

Le dépôt porte aussi **`vde2` et `uml-utilities`**, sans lesquels Marionnet ne peut pas tourner
et qu'*aucune* distribution RPM n'empaquette (mesuré sur Rocky 9 avec EPEL, CRB et epel-next, et
sur Fedora 42 et 44) ; ils sont construits ici à partir des paquets source Debian. `dnf` les
résout depuis le même répertoire, si bien que vous n'avez pas à savoir qu'ils existent — sauf sur
openSUSE, qui livre `vde2` et dont c'est le paquet qui est utilisé.

Les trois paquets de données sont les mêmes qu'au § 2, sous les mêmes noms, et nécessaires aux
mêmes choses. Le multilib étant natif ici, le noyau 32 bits n'a pas besoin d'un équivalent du
`dpkg --add-architecture` ; mais RHEL 10 a **supprimé tout le multilib 32 bits**, si bien que sur
cette famille `marionnet-kernels-i386` n'est tout simplement pas installable — c'est pourquoi il
est un paquet séparé : que son refus n'emporte pas celui de 64 bits. Il faut en prendre la
conséquence : pas de noyau 32 bits, donc pas de guignol ni de wheezy, donc **pas de routeur** sur
RHEL 10 (§ 2) — état temporaire, la publication d'une image de routeur 64 bits étant prévue.

## 4. N'importe quelle distribution — le tarball précompilé

L'application est aussi publiée sous la forme d'un tarball relocatable, nommé
`marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz`. Les deux derniers champs sont ceux qui
décident : l'artefact tourne sur une machine dont l'architecture est `<arch>` et dont la glibc
est **au moins** `<x.y>`, le versionnement des symboles de la glibc ne garantissant la
compatibilité que dans ce sens-là. L'artefact publié est construit sur **le plus ancien système
que nous servons** (actuellement Debian 12, glibc 2.36) : il tourne donc sur toutes les
distributions listées aux § 2 et § 3, et sur aucune plus ancienne — Rocky 9 et openSUSE Leap 15.6
le refusent en nommant la glibc.

Cette forme **n'est pas signée** : `SHA256SUMS`, que l'installeur contrôle pendant le
téléchargement, prouve que le fichier est arrivé entier, pas qui l'a écrit — le catalogue voyage
par la même route que les tarballs. Si cette distinction compte pour vous, prenez le § 2 ou le
§ 3.

Le plus simple est de laisser l'installeur choisir et déplier pour vous :

```bash
wget https://www.marionnet.org/download/marionnet-install.sh/marionnet-install.sh
bash marionnet-install.sh --binary --with-deps
```

`--binary` exige root (il appelle `sudo` si vous n'êtes pas root). Pour voir ce qui est publié
avant d'installer quoi que ce soit, demandez le catalogue — **y compris ce qu'il refuse, et
pourquoi** :

```bash
bash marionnet-install.sh --binary --fetch-only --list
```

`--list` se donne *avec un mode* : c'est le mode qui dit si l'application, les données, ou les
deux vous intéressent, et le script refuse de le deviner (sous son autre nom,
`marionnet-get-images`, le mode est implicite — § 5). À la main, si vous préférez :

```bash
xz -dc -T0 marionnet_<...>.tar.xz | tar xf -
cd marionnet_<...>/ && sudo ./install.sh --prefix /usr/local
```

`install.sh` est le *même* script dans les deux cas — l'installeur ne fait que lancer celui qui
voyage dans le tarball. Il copie `bin/` et `share/` sous le préfixe, écrit
`/etc/marionnet/marionnet.conf` (c'est ce qui permet au tarball de vivre n'importe où) et
installe la règle sudoers (§ 7). Par défaut il **nomme** les paquets apt manquants sans rien
installer ; `--with-deps` les installe, `--no-deps` ne regarde même pas. Son `--help` liste le
reste.

Les paquets dont Marionnet a besoin à l'exécution voyagent dans le tarball **comme donnée**, un
nom par ligne, dans `REQUIRED-PACKAGES-RUNTIME`. Sur un système de la famille Debian, à la main :

```bash
sudo apt install $(tr '\n' ' ' < REQUIRED-PACKAGES-RUNTIME)
```

## 5. Les images invitées et les noyaux UML

Quelle que soit la méthode qui a installé l'application, voici la commande qui propose les images
et les noyaux publiés sous forme de liste à cocher, et récupère ce que vous avez coché :

```bash
marionnet-get-images
```

Elle montre comme *déjà installée* — cochée, et non modifiable — toute image dont la date de
modification correspond au `MTIME` que son `.conf` enregistre, lequel est le champ que
user-mode-linux lui-même contrôle sur un *backing file*.

**Ne passez pas `--prefix` après une installation par paquet.** Sans `--prefix`, les images vont
là où *le Marionnet installé ici* les cherche — demandé à `marionnet --paths`, seul lecteur de la
cascade de configuration — soit `/usr/share/marionnet/...` pour un paquet et
`/usr/local/share/marionnet/...` pour un tarball. Un `--prefix` écrit à la main, c'est ainsi que
des images finissent dans un répertoire que l'application ne lit jamais : rien n'échoue, et les
images n'apparaissent simplement pas.

Deux des images (Debian wheezy, Debian trixie) sont délibérément hors d'apt et de dnf : elles
pèsent des gibioctets. La petite image `guignol` et les noyaux sont aussi disponibles en paquets
(§ 2, § 3), si vous préférez que votre gestionnaire de paquets en soit propriétaire.

**Pour une salle de TP sans accès à Internet**, faites une fois un miroir du répertoire de
release et pointez toutes les machines sur la copie — un répertoire local et une URL sont le même
argument :

```bash
marionnet-install.sh --fetch-only --from /srv/marionnet-mirror
```

## 6. Depuis les sources

Pour qui compte modifier Marionnet. La chaîne d'outils est **OCaml 5.4.1 par opam**, plus
camlp4 ; les images invitées et les noyaux viennent toujours du § 5.

```bash
git clone https://git.launchpad.net/marionnet && cd marionnet
make dependencies          # paquets apt (build + exécution), switch opam, paquets opam
dune build                 # un clone frais n'a besoin de rien d'autre : préprocesseurs camlp4,
                           # stubs C, version.ml et meta.ml sont tous construits par dune
make install-final-as-root # elle appelle sudo elle-même, pour la seule étape qui l'exige
```

Lancez les parties de `make dependencies` séparément (`make apt-dependencies`, `make opam-switch`,
`make opam-dependencies`) si vous voulez les voir une à une. Deux choses à savoir :

* `dune build` n'est **pas** un typecheck du projet entier — pour un exécutable, dune ne compile
  que ce que `marionnet.ml` atteint. `make check` compile tous les modules.
* pour lancer Marionnet depuis le switch opam au lieu de l'installer pour tout le système, utilisez
  `make install-for-testing` (et `make rebuild-for-final` / `make rebuild-for-testing` quand vous
  passez de l'un à l'autre : le préfixe est compilé dans le binaire comme valeur par défaut).

## 7. Ce qui reste dû après n'importe quelle méthode : la règle sudoers

Marionnet construit ses *taps* réseau avec `iproute2`, ce qui exige une règle sudoers **cadrée**.
Aucune méthode d'installation ne l'accorde automatiquement, et les paquets s'en abstiennent
délibérément : une installation de paquet ne peut pas savoir à quel humain une machine appartient.
Lancez, en tant qu'administrateur :

```bash
sudo marionnet-sudoers.sh install <user>...
```

Cela accorde le **socle** — bloc (a) — sans lequel rien ne marche. L'`install.sh` du tarball
l'installe pour vous (sauf `--no-sudoers`). Pour tout retirer :
`sudo marionnet-sudoers.sh uninstall`.

### 7.1 Accorder : un compte, plusieurs, ou une salle entière

La commande est **additive** : accorder le droit à une deuxième personne ne retire jamais celui de
la première, et `sudo marionnet-sudoers.sh uninstall <utilisateur>` retire une autorisation en
laissant les autres en place. Un compte qui n'existe pas est refusé — sudoers le nommerait
volontiers, et le droit tomberait dans les mains du premier à qui l'on créerait ce login.

Un principal est un compte, ou un **groupe** dans l'orthographe de sudoers. La salle de TP en est
la raison : celui qui prépare une salle ne connaît pas les logins des étudiants qui s'y
assiéront.

```bash
sudo groupadd marionnet                      # si le site n'a pas de groupe à lui
sudo gpasswd -a <login> marionnet            # (ou utilisez le groupe LDAP/AD existant)
sudo marionnet-sudoers.sh install %marionnet
```

Tout membre du groupe est alors autorisé, y compris celui qui s'inscrira la semaine prochaine.
Deux choses à savoir sur une autorisation de groupe. `ALL` est **refusé** : ce qu'un fichier
accorde doit avoir été décidé par quelqu'un, et cela engloberait les comptes système. Et la ligne
de création du tap, qui pour un compte nommé lie le tap à ce login, doit accepter n'importe quel
propriétaire pour un groupe — sudoers ne sait pas écrire « l'appelant » dans l'argument d'une
commande ; un membre peut donc créer un tap **appartenant à quelqu'un d'autre**, mais personne ne
gagne un tap qu'il puisse ouvrir et le confinement aux `mtap*` est intact.

`sudo -l -U <login>` est la question sur les droits effectifs ; `marionnet-sudoers.sh check`
répond sur les principaux que le fichier **nomme**, si bien qu'un membre d'un groupe autorisé n'en
est pas un. Nu, `check` est une question sur le **fichier** : est-il à jour pour les comptes qu'il
nomme (0), accordé mais écrit par une version antérieure de Marionnet (4), ou pas accordé du tout
(1) ? Sur un **4**, `check --explain` nomme ce qu'un rafraîchissement changerait, en commandes
gagnées et perdues — et rafraîchir, c'est `marionnet-sudoers.sh install`, qui est additif et ne
retire le droit de personne.

### 7.2 Les trois blocs, et ce que chacun fait à cette machine

À lire avant d'accorder quoi que ce soit au-delà du socle. Les trois blocs sont trois fichiers de
`/etc/sudoers.d/`, accordés à trois moments différents, et ils ne sont **pas** également
dangereux.

| Bloc | Accordé | Ce qu'il permet de faire à l'hôte |
|---|---|---|
| **(a) taps fantômes** | à l'installation, par l'administrateur | Créer et détruire des interfaces `mtap*`, leur donner l'adresse fixe `172.23.0.254/32` et y router `172.23.*`. Confiné aux `mtap*` : rien d'autre sur la machine n'est atteignable par là. Ce tap est aussi la route par laquelle les clients X11 d'un invité atteignent l'affichage de l'hôte — `xterm` sur une machine ou un routeur, et surtout **`wireshark`** lancé dans un routeur ou une machine pour capturer son propre trafic ; Marionnet en ouvre la porte par `xhost +172.23.0.254`. Sans ce bloc, Marionnet tourne en mode dégradé : pas de graphique depuis les invités, pas de terminaux de routeur. |
| **(b) NAT bridge** | à l'exécution, depuis l'interface | Construire le pont privé `mnbr*` et faire du NAT pour les invités derrière lui. |
| **(c) LAN bridge** | à l'exécution, depuis l'interface | Mettre la **carte réseau de l'hôte** dans un pont, pour que les invités soient sur le vrai réseau local. |

**(b), en détail.** Il crée un pont `mnbr*` portant l'adresse `.1/24` d'un réseau privé ; il met
`net.ipv4.ip_forward` **à 1**, ce qui vaut pour toute la machine et non par interface (Marionnet
ne le remet à 0 au démontage que s'il l'a lui-même mis à 1) ; il ajoute une règle `MASQUERADE` et
deux règles `FORWARD` avec `iptables`, **toutes porteuses du commentaire
`marionnet-natbridge:mnbr*`** — la règle sudoers exige ce marqueur, si bien qu'aucune règle
préexistante de votre pare-feu ne peut être ajoutée, modifiée ni supprimée par cette autorisation.
Facultativement, il démarre un **`dnsmasq` lié à ce seul pont** (DHCP en `.100-.200`, plus le DNS
pour les invités) — c'est pourquoi `dnsmasq-base` est une dépendance d'exécution. Facultativement
encore, l'IPv6 : une ULA `/64`, des *Router Advertisements* émis par ce même dnsmasq, et du NAT66
sur `ip6tables` — et comme le forwarding IPv6 n'est **pas** par interface, l'activer fait de tout
l'hôte un routeur, or un routeur ignore les annonces qu'il reçoit ; une porte minuscule et sans
argument (`marionnet-ipv6.sh`) mémorise donc et restitue `accept_ra`. La carte de l'hôte, ses
adresses et ses routes ne sont **jamais nommées** dans ce bloc : elles ne peuvent pas être
touchées par lui.

**(c), en détail — c'est le réseau de l'hôte, et cela ne peut pas être cadré.** Un LAN bridge
**est** la carte de l'hôte asservie à `mnlan0`, avec l'adresse IPv4 et la route par défaut de
l'hôte **déplacées sur le pont** et l'adresse MAC de la carte clonée dessus. Il y en a exactement
un par machine (une carte n'a qu'un maître), donc deux sessions Marionnet le partagent. À peser
avant de l'accorder :

* une fenêtre de quelques millisecondes pendant laquelle l'hôte n'a **plus de route de sortie**
  (l'adresse est posée sur le pont avant d'être retirée de la carte : elle n'est jamais nulle part) ;
* les machines virtuelles apparaissent **sur le vrai réseau local, avec leurs propres adresses
  MAC** — un commutateur avec *port security*, ou la politique réseau d'un campus, peut fort bien
  le refuser ;
* votre gestionnaire de réseau (NetworkManager, netplan, systemd-networkd) peut défaire la
  manipulation ou lutter contre elle ;
* les trois dernières lignes du fichier sudoers qu'il installe ne sont **restreintes à aucune
  interface** — `ip addr add|del * dev *` et `ip route add default via * dev *` — parce que la
  carte de l'hôte n'a pas de nom fixe. En clair : *ce compte peut reconfigurer l'adressage IPv4 de
  cette machine.* Aucun `iptables` n'est en jeu, pas de NAT, et pas d'IPv6 (pas géré du tout).

Le Wi-Fi est refusé (un point d'accès ne répond pas à plusieurs adresses MAC derrière une seule
association), de même qu'une carte déjà asservie au pont de quelqu'un d'autre, ou une route par
défaut ambiguë.

### 7.3 Accorder (b) sans (c)

C'est le **défaut**, et il n'y a rien à faire pour l'obtenir : un `install` nu n'accorde que (a),
et aucun des deux blocs de pont n'est jamais accordé à l'installation. Quand un utilisateur
démarre un composant *bridge*, Marionnet demande **son propre mot de passe sudo** et installe ce
bloc — (c) est donc déjà réservé aux comptes qui peuvent faire du sudo à l'exécution, bien après
l'installation faite par l'administrateur.

Pour donner d'avance le NAT bridge à une salle, sans qu'aucun mot de passe soit demandé et sans
que (c) entre jamais en jeu :

```bash
sudo marionnet-sudoers.sh install --enable-natbridge %marionnet
```

et, symétriquement, pour retirer un bloc en laissant le socle tranquille :

```bash
sudo marionnet-sudoers.sh uninstall --disable-lanbridge      # tous les comptes
sudo marionnet-sudoers.sh uninstall --disable-lanbridge <user>
```

### 7.4 Interdire un bloc pour de bon

Retirer une autorisation n'empêche pas l'utilisateur suivant de la redemander, depuis l'interface,
avec son propre mot de passe. Un administrateur qui ne veut pas qu'un LAN bridge soit construit sur
cette machine — jamais, par personne — le dit une fois :

```bash
sudo marionnet-sudoers.sh deny --lanbridge     # ou --natbridge, ou --bridges
```

Tant que ce veto est en place : le bloc est refusé à tout le monde, l'autorisation déjà en place
est **reprise** (la laisser ferait du veto un mensonge), et Marionnet **le dit dans son interface
au lieu de demander un mot de passe**. On le lève par `sudo marionnet-sudoers.sh allow
--lanbridge` — ce qui n'accorde rien : un utilisateur doit toujours demander. N'importe qui peut
consulter l'état, sans aucun privilège :

```bash
marionnet-sudoers.sh policy          # rc 0 si autorisé, 3 si interdit ; il dit lequel
```

Le veto est un fichier de `/etc/marionnet/`, lisible par tous à dessein : Marionnet doit connaître
la réponse *avant* de demander un mot de passe, et un fichier de `/etc/sudoers.d/` est en 0440
root, comme il se doit.

Le socle — bloc (a) — n'a **pas** de veto : c'est l'administrateur qui l'accorde à la main, donc
l'interdire reviendrait à ne pas taper la commande. Et un veto arrête une **erreur**, pas un
administrateur déterminé, qui édite `/etc/sudoers.d/` directement. Là où il mord, c'est la
configuration ordinaire d'une salle — un enseignant qui peut faire du sudo, des étudiants qui ne
peuvent pas — et c'est exactement là qu'un LAN bridge se construit par accident.

### 7.5 Le lancer, et contrôler l'installation

```bash
marionnet                    # ou : marionnet -r lab.mar, marionnet --exam, marionnet --help
```

`marionnet` est le nom que tape chaque page de cette documentation — le guide de l'enseignant, le
mode examen, les exemples du canal de contrôle, les scripts de TP. C'est un lien symbolique vers
`marionnet.native`, le nom que `dune install` donne à l'exécutable : le même programme, sous le
nom qu'emploie un humain.

Deux commandes répondent à *« cette installation est-elle bien celle que je crois ? »*, quelle
que soit la méthode qui l'a posée :

```bash
marionnet -v                 # version et révision
marionnet --paths            # où cette installation cherche images, noyaux et scripts
```

`--paths` est la réponse à *« les images n'apparaissent pas »* : il affiche les répertoires que la
cascade de configuration a effectivement résolus (§ 5).

## 8. Désinstaller Marionnet

* **apt** : `sudo apt purge marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol`
* **dnf** : `sudo dnf remove marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol`
  (`sudo zypper remove ...`, sur openSUSE)
* **tarball** : le `README` qu'il contient liste ce qu'il faut supprimer, préfixe par préfixe.

Dans les trois cas, la règle sudoers n'ayant jamais été accordée par l'installation, elle n'est
pas retirée par la désinstallation : `sudo marionnet-sudoers.sh uninstall`.

## 9. Quand quelque chose ne marche pas

| Symptôme | Ce que c'est |
|---|---|
| `server down, no route, wrong URL?` alors que le site est debout | pas de magasin de certificats — § 1 |
| apt dit que le dépôt est ignoré, et `apt-get update` sort quand même avec 0 | même cause, ou la ligne du `sources.list` a été modifiée ; apt rapporte cela comme un *avertissement* |
| `Missing key <empreinte>`, ou `signature verification failed` | le fichier de `/etc/apt/keyrings/` n'est pas la clef de l'archive — récupérez-la de nouveau (§ 2) et comparez l'empreinte |
| apt continue de proposer le paquet alors qu'il vient de refuser le dépôt | il réutilise l'index qu'il avait déjà : `sudo rm -rf /var/lib/apt/lists/*` puis `apt update` |
| `Failed to import OpenPGP keys`, ou dnf annonce que le dépôt n'a aucun paquet | le fichier de clef du § 3 est absent, n'a pas été accepté, ou n'est pas une clef du tout — récupérez-le de nouveau et contrôlez l'empreinte avant d'importer |
| le tarball est refusé, en nommant une glibc | votre distribution est plus ancienne que le plancher de compilation — § 4 |
| `marionnet-kernels-i386` est refusé, en nommant `libc6:i386` | `dpkg --add-architecture i386` — § 2 |
| Marionnet démarre mais les images invitées n'apparaissent pas | elles ont été déposées sous un préfixe que l'application ne lit pas — § 5, puis `marionnet --paths` |
| *Unsatisfied dependency* au démarrage | `vde2`, `graphviz` ou `uml-utilities` manque ; l'`install.sh` du tarball nomme ce qui manque, `--with-deps` l'installe |
| une machine virtuelle refuse de démarrer, les taps ne peuvent pas être construits | la règle sudoers — § 7 |
| rien ne s'ouvre quand un invité lance `wireshark` ou `xterm` | le bloc (a) n'est pas accordé (§ 7.2), ou l'hôte n'a pas d'affichage X |

## Où aller ensuite

Ces pages sont installées à côté de celle-ci ; sauf mention contraire, elles sont en anglais. Elles
vivent dans `doc-src/` du dépôt des sources, qui est aussi là où est publiée la clef d'archive des
§ 2 et § 3 :

```bash
git clone https://git.launchpad.net/marionnet
```

| Page | À lire pour |
|---|---|
| `INSTALL.md` | cette même page en anglais — c'est elle qui fait foi |
| `teacher-guide.md` | préparer un TP, conduire la séance, la noter |
| `scripting/README.md` | piloter Marionnet depuis un script, par le canal de contrôle |
| `exam-mode.md` | ce qu'une session d'examen enregistre |
| `project-format-v3.md` | le format de projet `.mar` |
