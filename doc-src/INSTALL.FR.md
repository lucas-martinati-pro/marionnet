# Installer Marionnet

> **Traduction française de `INSTALL.md`.** L'original anglais fait foi : en cas de divergence,
> c'est lui qu'il faut corriger, et cette page à sa suite.

*Quel canal prendre, ce que chacun dépose, et ce qu'une machine vous doit encore ensuite.*

Marionnet est publié par **trois canaux**, tous alimentés par le même répertoire de release sur
`www.marionnet.org` et portant tous le **même binaire**. Celui qu'il faut prendre dépend du
gestionnaire de paquets de votre machine, pas de ce que vous comptez faire de Marionnet :

| Votre machine | Prenez | § |
|---|---|---|
| Debian, Ubuntu et dérivées | le **dépôt apt** | § 2 |
| Fedora, famille RHEL (Rocky, AlmaLinux), openSUSE | le **dépôt dnf/zypper** | § 3 |
| tout le reste — ou vous ne voulez aucun gestionnaire de paquets | le **tarball précompilé** | § 4 |
| vous comptez modifier Marionnet | **depuis les sources** | § 6 |

Quel que soit le canal, les **images invitées et les noyaux UML se récupèrent séparément** (§ 5) :
ils pèsent des gibioctets, ils changent à leur propre rythme, et ce n'est pas à cela que sert un
gestionnaire de paquets. Marionnet démarre sans eux et le dit.

Tout chemin relatif de cette page est relatif **au répertoire où se trouve ce fichier** :
`doc-src/` dans les sources, `<prefix>/share/doc/marionnet/` sur une machine où Marionnet est
installé.

## 1. Avant toute chose, sur une Debian ou une Ubuntu minimale

Les trois canaux atteignent le site en **https**, et un système Debian ou Ubuntu *minimal* —
notamment une image de conteneur nue — ne porte **aucun magasin de certificats** (mesuré sur
Debian 12 et 13 et sur Ubuntu 24.04 et 26.04 ; les images de la famille RPM, elles, en ont un).
Sans lui, `apt` ne lira pas notre dépôt et l'installeur ne lira pas le catalogue, alors même que
le serveur est parfaitement debout :

```bash
sudo apt update && sudo apt install ca-certificates curl
```

`curl` est dans cette ligne pour la même raison : une image *slim* n'a pas non plus de
téléchargeur, et le § 2 récupère la clef de l'archive avec (`wget` fait tout aussi bien —
`wget -O` à la place de `curl -o`).

`marionnet-install.sh` diagnostique le cas du magasin de certificats **en le nommant** plutôt
qu'en accusant le réseau, mais il ne peut pas le réparer : installer ce paquet demande un
gestionnaire de paquets en état de marche, c'est-à-dire précisément ce qui est en jeu.

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

### La clef, et ce que signer achète — ou n'achète pas

Le fichier `Release` du dépôt est signé, et c'est `signed-by=` qui fait qu'apt le vérifie. La
clef est :

```
Marionnet Archive Signing Key <loddo@lipn.univ-paris13.fr>
4A65 3434 0BF9 7733 E74C  9DFC 12E4 6000 225F 0E56
```

**Remarquez d'où vient la clef : `git.launchpad.net`, et non `www.marionnet.org`.** C'est tout
l'intérêt de la manœuvre, et cela vaut deux minutes d'attention.

Sans signature, tout ce que vous téléchargez n'est protégé que par https, qui prouve que le
serveur n'a pas été usurpé — et rien du tout sur qui a écrit les paquets. Qui contrôle ce serveur
réécrit les paquets *et* les empreintes qui en répondent : tout reste cohérent, tout vérifie, et
tout est faux. La signature déplace le point de confiance vers une clef privée qui ne vit pas sur
le serveur.

*Ce qu'elle protège, concrètement* : les machines **déjà installées**. Une telle machine ne relit
jamais cette page ; à chaque `apt upgrade` elle contrôle contre la clef déjà présente sur son
disque. Qui prendrait le serveur demain ne peut rien leur pousser — apt refuse, et le dit. Sans
signature, une salle entière prendrait une mise à jour piégée **en silence**, sur des machines où
Marionnet installe une règle sudoers.

*Ce qu'elle ne protège pas* : votre toute première installation, si vous apprenez tout d'un site
compromis — la page nommerait alors une autre clef, et tout vérifierait. Aucune signature ne
résout cela (le trousseau de Debian lui-même arrive dans une ISO téléchargée depuis un site web).
Ce qui rompt le cercle, c'est de comparer l'empreinte ci-dessus avec **une source qui n'est pas
cette page** : le dépôt git, un polycopié imprimé, une machine où Marionnet est déjà installé.
Dans une salle de TP, l'empreinte lue à voix haute une fois en début de semestre règle la
question pour tout le monde.

**Contrôlez ce que vous avez récupéré — cette étape n'est pas facultative ici**, et pas seulement
pour la raison ci-dessus. Mesuré : `git.launchpad.net` répond `200` la plupart du temps et,
environ une requête sur six, un `302` vers sa page de connexion OpenID. `curl` écrira sans
sourciller dans le fichier ce qui lui est revenu : une récupération de clef peut donc vous
laisser tranquillement autre chose qu'une clef. (N'ajoutez **pas** `-L` : cela suit la
redirection et écrit la *page de connexion*, ce qui est pire — un échec qui ressemble à une
réussite.)

```bash
sudo apt install gnupg
gpg --show-keys /etc/apt/keyrings/marionnet.asc     # doit afficher l'empreinte ci-dessus
```

Si autre chose s'affiche — ou rien — récupérez-la de nouveau. apt n'a pas besoin de `gnupg` pour
vérifier le dépôt (il a son propre vérificateur) ; vous en avez besoin, vous, uniquement pour
*lire* ce que vous avez récupéré.

`wget -O /etc/apt/keyrings/marionnet.asc <url>` fait tout aussi bien, avec la même réserve.

`apt install marionnet` installe **l'application seule** — les paquets de données sont des
`Suggests:`, afin que cette commande veuille dire ici la même chose que `dnf install marionnet`
au § 3. Les trois autres paquets, tous facultatifs :

| Paquet | Ce qu'il porte |
|---|---|
| `marionnet-kernels` | le noyau UML 64 bits |
| `marionnet-fs-guignol` | la petite image invitée, machine *et* routeur |
| `marionnet-kernels-i386` | le noyau UML 32 bits, pour les vieux couples noyau/système de fichiers |

`marionnet-kernels-i386` exige une **architecture étrangère activée sur votre machine**, parce
que l'interpréteur du noyau 32 bits est `/lib/ld-linux.so.2` et que seul `libc6:i386` possède ce
chemin :

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install marionnet-kernels-i386
```

Sans cela, apt refuse le paquet en nommant `libc6:i386`. C'est pourquoi le noyau 32 bits est un
paquet à part : activer une architecture étrangère est une décision, et elle n'a pas à être
imposée à tous ceux qui veulent le 64 bits.

**Si un tarball Marionnet (§ 4) a d'abord été installé sur cette machine**,
`/etc/marionnet/marionnet.conf` existe déjà et dpkg demandera quoi en faire — et un
`apt install` *non interactif* **échoue** là, parce que `DEBIAN_FRONTEND=noninteractive`
gouverne *debconf*, et non l'invite de conffile de dpkg. Pour garder la configuration que vous
avez déjà :

```bash
sudo apt install -o Dpkg::Options::=--force-confold marionnet
```

La version du fichier livrée par le paquet est alors laissée à côté, sous le nom
`marionnet.conf.dpkg-dist`. Notez que les deux fichiers divergent sur un point qui compte : un
paquet installe sous `/usr`, un tarball sous `/usr/local`.

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

C'est **la même clef qu'au § 2** — même empreinte, même endroit d'où la récupérer, et tout ce que
le § 2 dit de ce qu'une signature achète ou n'achète pas s'applique ici mot pour mot. La ligne du
milieu du bloc ci-dessus est celle qu'il ne faut pas sauter, et elle vient **avant**
`rpm --import` à dessein : importer *est* l'acte de faire confiance, donc regarder ensuite ce
qu'on a récupéré serait regarder trop tard. La réserve est la même qu'au § 2 —
`git.launchpad.net` répond une redirection environ une requête sur six, et `curl` écrit ce qui
lui est revenu.

Si `gpg` n'est pas sur la machine : `sudo dnf install gnupg2` (`zypper install gpg2` sur
openSUSE). Ni `dnf` ni `rpm` n'en ont besoin — ils ont leur propre vérificateur ; vous en avez
besoin, vous, uniquement pour *lire* la clef, exactement comme au § 2.

Ce qui diffère, c'est la *forme* de la vérification, pas sa force. Là où apt a une signature sur
`Release` qui couvre tous les paquets par leur empreinte, rpm a **deux** mécanismes, et la
strophe demande les deux :

| Réglage | Ce qu'il vérifie |
|---|---|
| `gpgcheck=1` | **chaque paquet**, par une signature que `rpmsign` a logée dans le fichier lui-même |
| `repo_gpgcheck=1` | **l'index**, par le `repodata/repomd.xml.asc` posé à côté |

Notez aussi que la strophe nomme la clef par un **fichier local**
(`gpgkey=file:///etc/pki/rpm-gpg/…`) et non par une URL — d'où le fait que vous la récupériez
vous-même dans le bloc ci-dessus. C'est délibéré, et mesuré : `dnf` récupère `gpgkey=` lui-même
et *suit les redirections*, si bien qu'un `gpgkey=` nommant `git.launchpad.net` télécharge la
page de connexion une fois sur six et fait mourir l'installation sur `Failed to import OpenPGP
keys` — après avoir téléchargé tous les paquets. Contrairement à `curl`, on ne peut pas dire à
`dnf` de ne pas suivre. Récupérer la clef à la main rétablit du même coup l'étape qui compte :
*une clef que le gestionnaire de paquets va chercher tout seul est une clef que personne n'a
regardée*.

`dnf` peut encore vous montrer une empreinte et vous demander s'il faut accepter la clef : il
tient un trousseau à lui pour `repo_gpgcheck`, que le `rpm --import` ci-dessus n'alimente pas.
Comparez ce qu'il affiche avec l'empreinte du § 2 avant de répondre oui.

**Sur la famille RHEL, activez d'abord EPEL** : `gtksourceview3`, l'une des dépendances
d'exécution de Marionnet, y vit et non dans les dépôts de base.

```bash
sudo dnf install epel-release
```

Le dépôt porte aussi **`vde2` et `uml-utilities`**, sans lesquels Marionnet ne peut pas tourner
et qu'*aucune* distribution RPM n'empaquette — mesuré sur Rocky 9 avec EPEL, CRB et epel-next, et
sur Fedora 42 et 44. Ils sont construits ici à partir des paquets source Debian, série de patches
comprise. `dnf` les résout depuis le même répertoire, si bien que vous n'avez pas à savoir qu'ils
existent ; sur openSUSE, qui *livre* `vde2`, c'est le paquet de la distribution qui est utilisé
et le nôtre n'est pas tiré.

Les paquets de données facultatifs sont les trois mêmes qu'au § 2, sous les mêmes noms. Le paquet
du noyau 32 bits n'a pas ici d'équivalent du `dpkg --add-architecture` — le multilib est natif —
mais RHEL 10 a **supprimé tout le multilib 32 bits**, si bien que sur cette famille
`marionnet-kernels-i386` n'est tout simplement pas installable ; c'est pourquoi il est un paquet
séparé : que son refus n'emporte pas celui de 64 bits.

## 4. N'importe quelle distribution — le tarball précompilé

L'application est aussi publiée sous la forme d'un tarball relocatable, nommé
`marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz`. Les deux derniers champs sont ceux qui
décident : l'artefact tourne sur une machine dont l'architecture est `<arch>` et dont la glibc
est **au moins** `<x.y>` — un binaire lié dynamiquement exige une glibc pas plus ancienne que
celle contre laquelle il a été lié, et le versionnement des symboles de la glibc ne garantit que
ce sens-là.

L'artefact publié est construit sur **le plus ancien système que nous servons** (actuellement
Debian 12, glibc 2.36) : il tourne donc sur toutes les distributions listées aux § 2 et § 3.

Ce canal **n'est pas signé**. L'empreinte de chaque artefact est dans `SHA256SUMS`, que
l'installeur contrôle pendant le téléchargement — cela prouve que le fichier est arrivé entier,
pas qui l'a écrit, puisque le catalogue voyage par la même route que les tarballs. Les deux
canaux de paquets (§ 2 et § 3), eux, sont signés. Si cette distinction compte pour vous, prenez
l'un des deux. Le tarball ne tourne *pas* sur Rocky 9 ni sur openSUSE Leap 15.6, dont la glibc
est plus ancienne ; toutes deux le refusent en nommant la glibc.

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

Quel que soit le canal qui a installé l'application, voici la commande qui propose les images et
les noyaux publiés sous forme de liste à cocher, et récupère ce que vous avez coché :

```bash
marionnet-get-images
```

Elle montre comme *déjà installée* — cochée, et non modifiable — toute image dont la date de
modification correspond au `MTIME` que son `.conf` enregistre, lequel est le champ que
user-mode-linux lui-même contrôle sur un *backing file*.

**Ne passez pas `--prefix` après une installation par paquet.** Sans `--prefix`, les images vont
là où *le Marionnet installé ici* les cherche — demandé à `marionnet.native --paths`, seul
lecteur de la cascade de configuration — soit `/usr/share/marionnet/...` pour un paquet et
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

`make dependencies` installe les dépendances apt de compilation, crée le switch opam et installe
les paquets opam ; lancez ses parties séparément (`make apt-dependencies`, `make opam-switch`,
`make opam-dependencies`) si vous voulez les voir une à une.

Deux choses à savoir avant de compiler :

* `dune build` n'est **pas** un typecheck du projet entier — pour un exécutable, dune ne compile
  que ce que `marionnet.ml` atteint. `make check` compile tous les modules.
* pour lancer Marionnet depuis le switch opam au lieu de l'installer pour tout le système, utilisez
  `make install-for-testing` (et `make rebuild-for-final` / `make rebuild-for-testing` quand vous
  passez de l'un à l'autre : le préfixe est compilé dans le binaire comme valeur par défaut).

## 7. Ce qui reste dû après n'importe quel canal : la règle sudoers

Marionnet construit ses *taps* réseau avec `iproute2`, ce qui exige une règle sudoers **cadrée**.
Aucun canal ne l'accorde automatiquement, et les paquets s'en abstiennent délibérément : une
installation de paquet ne peut pas savoir à quel humain une machine appartient. Lancez, en tant
qu'administrateur :

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
assiéront, et ne peut pas attendre de les connaître.

```bash
sudo groupadd marionnet                      # si le site n'a pas de groupe à lui
sudo gpasswd -a <login> marionnet            # (ou utilisez le groupe LDAP/AD existant)
sudo marionnet-sudoers.sh install %marionnet
```

Tout membre du groupe est alors autorisé, y compris celui qui s'inscrira la semaine prochaine.
Deux choses à savoir sur une autorisation de groupe : `ALL` est **refusé** (ce qu'un fichier
accorde doit avoir été décidé par quelqu'un, et cela engloberait les comptes système) ; et la
ligne de création du tap, qui pour un compte nommé lie le tap à ce login, doit accepter n'importe
quel propriétaire pour un groupe — sudoers ne sait pas écrire « l'appelant » dans l'argument d'une
commande. Un membre peut donc créer un tap **appartenant à quelqu'un d'autre** ; personne ne
gagne un tap qu'il puisse ouvrir, et le confinement aux `mtap*` est intact. `sudo -l -U <login>`
est la question sur les droits effectifs (`marionnet-sudoers.sh check` répond sur les principaux
que le fichier **nomme** ; un membre d'un groupe autorisé n'en est pas un).

### 7.2 Les trois blocs, et ce que chacun fait à cette machine

À lire avant d'accorder quoi que ce soit au-delà du socle. Les trois blocs sont trois fichiers de
`/etc/sudoers.d/`, accordés à trois moments différents, et ils ne sont **pas** également
dangereux.

| Bloc | Accordé | Ce qu'il permet de faire à l'hôte |
|---|---|---|
| **(a) taps fantômes** | à l'installation, par l'administrateur | Créer et détruire des interfaces `mtap*`, leur donner l'adresse fixe `172.23.0.254/32` et y router `172.23.*`. Confiné aux `mtap*` : rien d'autre sur la machine n'est atteignable par là. Sans lui, Marionnet tourne en mode dégradé — pas de graphique dans les invités, pas de terminaux de routeur. |
| **(b) NAT bridge** | à l'exécution, depuis l'interface | Construire le pont privé `mnbr*` et faire du NAT pour les invités derrière lui. |
| **(c) LAN bridge** | à l'exécution, depuis l'interface | Mettre la **carte réseau de l'hôte** dans un pont, pour que les invités soient sur le vrai réseau local. |

**(b), en détail — il ne touche jamais l'interface de l'hôte, et c'est ce qui le rend sûr.** Il
crée un pont `mnbr*` portant l'adresse `.1/24` d'un réseau privé ; il met
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
argument (`marionnet-ipv6.sh`) mémorise donc et restitue `accept_ra`, pour que l'hôte ne perde pas
sa propre route IPv6 quelques minutes plus tard. La carte de l'hôte, ses adresses et ses routes ne
sont **jamais nommées** dans ce bloc : elles ne peuvent pas être touchées par lui.

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

Deux choses qu'il est honnête de savoir. Le socle — bloc (a) — n'a **pas** de veto : c'est
l'administrateur qui l'accorde lui-même, à la main, donc l'interdire reviendrait à ne pas taper la
commande. Et un veto arrête une **erreur**, pas un administrateur déterminé : qui peut faire du
`sudo` sans restriction édite `/etc/sudoers.d/` directement et n'a besoin de la permission de
personne. Là où il mord vraiment, c'est la configuration ordinaire d'une salle — un enseignant qui
peut faire du sudo, des étudiants qui ne peuvent pas — et c'est exactement là qu'un LAN bridge se
construit par accident.


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
| Marionnet démarre mais les images invitées n'apparaissent pas | elles ont été déposées sous un préfixe que l'application ne lit pas — § 5 |
| *Unsatisfied dependency* au démarrage | `vde2`, `graphviz` ou `uml-utilities` manque ; le canal du tarball nomme ce qui manque, `--with-deps` l'installe |
| une machine virtuelle refuse de démarrer, les taps ne peuvent pas être construits | la règle sudoers — § 7 |

## Où aller ensuite

Ces pages sont installées à côté de celle-ci ; elles sont en anglais.

| Page | À lire pour |
|---|---|
| `teacher-guide.md` | préparer un TP, conduire la séance, la noter |
| `scripting/README.md` | piloter Marionnet depuis un script, par le canal de contrôle |
| `exam-mode.md` | ce qu'une session d'examen enregistre |
| `project-format-v3.md` | le format de projet `.mar` |
