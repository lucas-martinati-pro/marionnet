# Installation et construction des paquets

`../install.sh` délègue à `install.sh` dans ce dossier. Le moteur `.deb` installe
le paquet tout-en-un et les images demandées ; `--tarball` délègue au moteur
`bin/scripts/marionnet-install.sh`.

## Configuration des droits réseau

Depuis le 5 octobre 2026, le moteur `.deb` passe uniquement par
`marionnet-sudoers.sh install <utilisateur>`, puis par
`marionnet-sudoers.sh check <utilisateur>`. Le premier conserve les comptes déjà
accordés et valide les règles générées ; le second vérifie leur contenu et cherche
un refus de sudo, notamment lorsqu'une règle ultérieure annule `NOPASSWD`.

Un échec rend l'installation **non réussie** (code de sortie 1) et conserve le
diagnostic d'origine. Les paquets installés auparavant ne sont pas désinstallés.
Le script indique la commande permettant de reprendre après correction.

L'ancien secours écrivait directement `/etc/sudoers.d/marionnet`, en accordant
`/usr/sbin/ip` sans restriction d'arguments, et masquait l'erreur de l'outil
principal. Ce secours a été supprimé : une erreur de configuration ne justifie
pas d'accorder davantage de droits. Le même chemin s'applique avec sudo classique
et sudo-rs ; aucune variante de règle n'est générée dans ce dossier.

Une ancienne règle issue de ce secours sera remplacée par les règles générées lors
d'une **configuration réussie**. En cas de refus, l'installeur ne prétend pas l'avoir
corrigée et ne la réécrit pas lui-même. Ce correctif ne change pas les commandes
privilégiées définies par `bin/scripts/marionnet-sudoers.sh`.

## Vérification sans modifier l'hôte

```sh
bash dist/install-sudoers.bench.sh
# Inclus également dans :
opam exec -- dune runtest
```

Le banc exécute l'installeur complet sur une copie temporaire. Téléchargement,
paquets, sudo, détection d'architecture, présence de l'interpréteur i386 et bibliothèques sont substitués ; le faux
sudo n'exécute jamais ses arguments. Les fichiers de règles observés sont des
fixtures privées, sans écriture dans `/etc`, installation de paquet ou accès réseau.

Quatre scénarios : réussite ; règle rejetée à l'installation ; outil absent ;
règle installée mais refusée au contrôle. Le banc vérifie les appels avec le compte
cible, la conservation des règles, le diagnostic et l'absence d'annonce de succès
après une erreur. Avant le correctif, il échoue sur 15 assertions, dont le
remplacement de la règle par le secours permissif. Il vérifie les erreurs
rapportées par les outils, sans prétendre valider une installation réelle sous
chaque implémentation de sudo.
