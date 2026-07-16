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
marionnet-sudoers.sh print      # affiche la règle attendue (sans rien installer)
marionnet-sudoers.sh install    # installe /etc/sudoers.d/marionnet (se ré-exécute via sudo)
marionnet-sudoers.sh check      # (root) le fichier installé est-il à jour ?
marionnet-sudoers.sh uninstall  # retire la règle
```

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

`marionnet-sudoers.sh install` génère une règle pour **un** utilisateur ; le plus simple
reste donc une ligne `install <login>` par compte de la salle. Pour une règle unique par
groupe, partez de la sortie de `print` et éditez-la à la main (puis validez par
`visudo -cf`) :

- préfixez chaque ligne de commande par `%marionnet` au lieu du login ;
- la ligne `tuntap add … mode tap user <login>` doit devenir `… mode tap user *` :
  chaque membre y passera son propre login (Marionnet génère `user $USER`). Le joker
  n'autorise que la *propriété* du tap, toujours confiné à `mtap*`.

C'est toujours moins exposé que l'ancienne socket 0666 du daemon, qui offrait les mêmes
créations de taps à **tous** les comptes locaux, sans aucune déclaration de l'admin.

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
