# Doc d'administration — taps Marionnet et world_bridge

> Doc d'exploitation (indépendante du chantier qui l'a produite ; contexte historique :
> `docs/daemon-elimination-study.md`). Publics : l'utilisateur qui installe Marionnet sur
> son poste, et l'admin d'une salle de TP.

Depuis l'élimination de `marionnet-daemon` (le service root permanent historique),
Marionnet crée ses interfaces réseau privilégiées — les taps `mtap*` — par
`sudo -n ip …` (iproute2), sous le contrôle d'une **règle sudoers étroite**. Deux usages :

- **tap eth42** (un par machine/routeur virtuel) : canal hôte↔invité (X11, telnet
  quagga) — adresse `172.23.0.254/32`, route host-specific vers l'invité ;
- **tap world_bridge** : tap promisc raccordé à un **bridge géré par l'admin**, pour
  brancher un réseau virtuel sur un réseau réel.

## 1. La règle sudoers (poste personnel)

Source unique : le script `marionnet-sudoers.sh` (installé dans `$PREFIX/bin/`, présent
dans les sources sous `bin/scripts/`).

```
marionnet-sudoers.sh print               # affiche la règle attendue (sans rien installer)
marionnet-sudoers.sh install [USER...]   # installe /etc/sudoers.d/marionnet (se ré-exécute via sudo)
marionnet-sudoers.sh check   [USER...]   # (root) le fichier installé est-il à jour ?
marionnet-sudoers.sh check --explain     # (root) ... et ce qu'un rafraîchissement changerait
marionnet-sudoers.sh uninstall [USER...] # retire l'autorisation (le fichier entier si aucun USER)
marionnet-sudoers.sh deny  --lanbridge   # (root) interdit ce bloc sur cette machine
marionnet-sudoers.sh allow --lanbridge   # (root) lève l'interdiction (n'accorde rien)
marionnet-sudoers.sh policy [--lanbridge] # rc 0 autorisé / 3 interdit — SANS privilège
```

Un fichier autorise une **liste** de comptes, et `install` est **additif** : les comptes déjà
présents sont conservés (et leurs règles régénérées). Accorder le droit à un deuxième utilisateur
ne retire donc jamais celui du premier — `uninstall <login>` est le seul geste qui retire. Un
compte inexistant est **refusé** : `visudo` accepterait volontiers `student42`, et le droit
tomberait dans les mains du premier venu à qui l'on créerait ce login.

`make install-final-as-root` installe la règle dans le même geste. Sans elle, Marionnet
fonctionne en **mode dégradé** (pas de X11 dans les invités, pas de world_bridge) et
affiche au démarrage la commande `install` à lancer.

Ce que la règle autorise — et rien d'autre : les six commandes `ip` de Marionnet,
**confinées aux interfaces `mtap*`**, avec adresse (`172.23.0.254/32`) et réseau routé
(`172.23.*`) littéraux. Les noms de taps sont générés (`mtap<pid>-<seq>`), jamais saisis.
Périmètre plus étroit que l'ancien daemon, dont la socket en mode 0666 offrait les mêmes
créations de taps à **tous** les comptes locaux, sans opt-in de l'admin.

## 2. Le bridge du world_bridge

Le composant world_bridge suppose un bridge préexistant, créé par l'admin, dont le nom est
donné par la variable de configuration `MARIONNET_BRIDGE` (`/etc/marionnet/marionnet.conf`).
Création (persistance selon votre gestionnaire réseau — NetworkManager, netplan,
systemd-networkd) :

```
sudo ip link add name br0 type bridge
sudo ip link set br0 up
# facultatif : y raccorder une interface physique
sudo ip link set eth0 master br0
```

Au lancement d'un world_bridge, Marionnet crée un tap `mtap*` (promisc, up), le raccorde
au bridge (`ip link set … master`), et y attache un `vde_switch -tap` **non privilégié**.
Le tap disparaît avec le projet (`ip link del`, qui détache du bridge implicitement).

## 3. Salle de TP : la règle pour un groupe

Un principal peut être un **groupe**, dans l'orthographe de sudoers — c'est le cas d'usage
d'une salle : celui qui la prépare ne connaît pas les logins des étudiants qui s'y assiéront.

```
sudo groupadd marionnet                        # ou le groupe LDAP/AD du site
sudo gpasswd -a <login> marionnet
sudo marionnet-sudoers.sh install %marionnet   # (a) pour tout le groupe
sudo marionnet-sudoers.sh install --enable-natbridge %marionnet   # + (b), sans (c)
```

Plus rien à éditer à la main : le script écrit la règle du groupe lui-même, et `visudo -cf`
la valide avant adoption. Deux propriétés à connaître :

- **`ALL` est refusé.** Ce qu'un fichier accorde doit avoir été décidé par quelqu'un, et `ALL`
  engloberait les comptes système. Le refus nomme la sortie (`groupadd` + `gpasswd`).
- **La propriété du tap devient un joker pour un groupe** : `ip tuntap add … mode tap user *`
  au lieu de `… user <login>`. sudoers ne sait pas écrire « l'appelant » dans l'argument d'une
  commande (il n'y a pas d'expansion `%u` là), donc la ligne ne peut plus lier le tap au login
  du demandeur. Ce que ça ouvre, mesuré : un membre peut créer un tap **appartenant à un autre
  compte** — une nuisance, pas une entrée, un tap dont on n'est pas propriétaire ne s'ouvrant
  pas. Le confinement aux `mtap*` est intact (mesuré : `ip tuntap add dev eth0 …` est refusé),
  et cela reste plus étroit que la ligne `ip link set mtap* *` que **tout** compte autorisé
  possède déjà. Un compte nommé, lui, garde sa règle exacte.

`marionnet-sudoers.sh check` répond sur les principaux que le fichier **nomme** : un membre
d'un groupe autorisé n'en est pas un. La question sur les droits **effectifs** est
`sudo -l -U <login>`.

**`check` nu est une question sur le FICHIER** — *est-il à jour pour les comptes qu'il nomme ?* —
et n'implique **aucun** compte : contrairement à `print` et `install`, qui produisent un contenu
et doivent donc savoir « pour qui », il ne produit rien. Nommer des USER pose l'autre question,
*les grante-t-il*. Codes de sortie : **0** à jour, **4** accordé mais **périmé** (écrit par une
version antérieure), **1** non accordé. `--explain` nomme alors l'écart en **commandes**
accordées — `+` gagnées, `-` perdues — mesurées sur ce fichier-ci, et ne rend rien quand l'écart
n'est que dans le texte (en-tête, ligne `# principals:`).

C'est toujours moins exposé que l'ancienne socket 0666 du daemon, qui offrait les mêmes
créations de taps à **tous** les comptes locaux, sans aucune déclaration de l'admin.

Ce que chaque bloc fait à la machine — et pourquoi (b) est sûr là où (c) ne peut pas l'être —
est écrit pour l'administrateur au § 7.2 de `doc-src/INSTALL.md` (et sa traduction FR).

## 4. Variante « zéro sudo » : taps pré-provisionnés (non câblée)

Pour un campus refusant toute règle sudo : le noyau permet de s'attacher **sans
privilège** à un tap persistant préexistant dont on est propriétaire (owner/group). L'admin
peut donc pré-créer N taps raccordés au bridge, owned par le groupe des étudiants :

```
sudo ip tuntap add dev wbtap0 mode tap group marionnet
sudo ip link set wbtap0 promisc on up master br0
# … répéter pour wbtap1..wbtapN
```

**Limite actuelle** : la GUI ne sait pas encore *découvrir* ces taps pré-provisionnés —
elle crée toujours le sien par sudo. Cette variante est documentée comme cible : elle
sera câblée si le besoin se concrétise (de même que l'étape « netns de session », qui
supprimerait le besoin de sudo pour les taps eth42 ; cf. l'étude § 4.1 B et D).
