# Marionnet @VERSION@ — Pare-feu fonctionnel et nouvelle icône

Cette mise à jour corrige le pare-feu des invités 32 bits, ajoute Marionnet au
menu des applications et simplifie le choix du paquet à installer.

## Pare-feu et NAT

- Le noyau UML `6.12.95-i386` intègre désormais Netfilter, le suivi des connexions
  et le NAT. Les commandes `iptables` et `ip6tables` peuvent utiliser les tables
  de filtrage et de NAT dans Debian Wheezy et Guignol.
- Les fonctions nécessaires sont intégrées au noyau : les invités n'ont pas
  besoin d'un dossier `/lib/modules` pour les charger.
- Le paquet tout-en-un embarque le noyau corrigé. Les prochaines constructions
  vérifient les options du pare-feu pour éviter de réintroduire ce problème.

## Raccourci et icône

- Une nouvelle icône accompagne l'application, ses fenêtres et son raccourci.
- Marionnet apparaît dans le menu des applications grâce au fichier `.desktop`,
  installé aussi lors d'une mise à jour du paquet.
- L'image de l'icône est centralisée dans les sources : son remplacement met à
  jour les différents emplacements lors de la construction du paquet.

## Installation

- `./install.sh` installe par défaut le paquet **tout-en-un publié**, qui contient
  l'application, les noyaux UML 32 et 64 bits et Guignol.
- Le script ajoute Debian Wheezy depuis son paquet partagé, sans devoir la
  télécharger à nouveau à chaque mise à jour de l'application.
- `./install.sh --local` construit et installe les modifications du dépôt local.
- Les paramètres des composants sont partagés entre les scripts d'installation
  et de construction. Les dépendances du paquet sont calculées depuis le binaire
  effectivement distribué, construit sur Ubuntu 22.04.
- Les téléchargements restent vérifiés avec `SHA256SUMS`. `BUILD_ID` permet de
  détecter aussi une nouvelle construction publiée sous le même numéro.

Depuis une installation existante, utilisez la proposition de mise à jour ou :

```bash
marionnet-update
```

Depuis le dépôt :

```bash
git pull
./install.sh --release @VERSION@
```

## Vérifications

Le noyau corrigé a été testé avec de vrais démarrages de Debian Wheezy et Guignol,
les tables IPv4/IPv6 et des échanges réseau avec DNAT, SNAT et MASQUERADE. Les
installations et réinstallations du correctif ont été vérifiées sur Ubuntu 22.04,
Ubuntu 24.04 et Debian 12. Le raccourci et l'installation de l'icône ont également
été vérifiés localement.

Les images des distributions invitées et le format des projets sont conservés.
