# Marionnet 1.0.460 — Interface modernisée et utilisation plus fluide

Cette version améliore l’espace de travail, rend le dessin du réseau interactif
et ajoute l’annulation des modifications. Elle fiabilise aussi les sauvegardes
et l’installation, avec des messages plus lisibles dans le terminal.

## Une interface plus compacte

- Les menus sont réunis dans la barre de titre GTK. Les boutons redondants
  Nouveau, Ouvrir et Enregistrer sont retirés ; ces actions restent accessibles
  dans le menu **Projet**, avec `Ctrl+N`, `Ctrl+O` et `Ctrl+S`.
- La palette affiche par défaut les icônes des composants avec leurs infobulles.
  Le bouton **Aa** permet d’afficher ou de masquer leurs libellés.
- Une pastille **•** indique les modifications non enregistrées. Le titre devient
  `• Marionnet - fichier.mar`, puis `Marionnet - fichier.mar` après sauvegarde.
- La fenêtre s’adapte à la taille de l’écran. Les tableaux et les réglages du
  dessin défilent lorsque leur contenu dépasse l’espace disponible.
- Des compteurs indiquent le nombre de composants, de câbles et de composants
  actifs. L’espace de travail vide explique comment commencer un projet.

## Annuler et rétablir les modifications

Le menu **Édition** propose désormais **Annuler** (`Ctrl+Z`) et **Rétablir**
(`Ctrl+Y` ou `Ctrl+Maj+Z`). L’historique conserve jusqu’à **30 modifications** :
ajout, suppression et changement des propriétés des composants ou des câbles.

La restauration comprend la topologie, les paramètres associés et les scripts
de démarrage. Les fichiers nécessaires à un composant supprimé sont retenus
sans recopier ses gros disques différentiels. Les raccourcis respectent aussi
l’édition de texte dans les champs qui ont le focus.

Cette fonction s’utilise sur un **réseau arrêté**. L’historique est réinitialisé
au changement de projet ; une nouvelle modification abandonne les opérations
encore rétablissables. Il ne rembobine pas le contenu des disques, les opérations
de démarrage/arrêt ni les modifications directes des cellules des tableaux.
Les restrictions du mode examen restent appliquées.

## Un dessin du réseau interactif

Les équipements et les câbles peuvent être manipulés directement depuis le
dessin, avec des actions adaptées à leur état :

- **Clic** : sélectionner un composant, afficher son contour et son nom.
- **Double-clic** ou **Entrée** : ouvrir ses propriétés.
- **Clic droit**, touche **Menu** ou **Maj+F10** : ouvrir les actions contextuelles,
  notamment les propriétés, la suppression et les actions de fonctionnement
  disponibles.
- **Suppr** : demander la suppression avec confirmation.
- **Échap** : désélectionner.
- **Ctrl+molette** : zoomer de **25 % à 300 %**, sans relancer Graphviz ni marquer
  le projet comme modifié.

Les zones cliquables suivent le rendu courant, y compris après un changement
de projet. Le menu contextuel est rattaché à sa fenêtre parente pour permettre
son positionnement sous Wayland. Le placement des composants reste automatique ;
le déplacement manuel et la création de câbles par glisser-déposer ne font pas
partie de cette version.

## Des dialogues de configuration cohérents

Les neuf types de composants partagent une présentation commune : machines,
routeurs, concentrateurs, commutateurs, câbles, nuages, ponts LAN, ponts NAT et
passerelles Internet.

- En-tête avec icône, champs **Nom** et **Étiquette**, et boutons
  **Aide / Annuler / Valider** homogènes.
- Validation immédiate des noms : un nom invalide ou déjà utilisé désactive
  le bouton de confirmation et affiche une indication dans le formulaire.
- Les fenêtres utilisent la hauteur disponible sur l’écran. Les paramètres
  défilent uniquement lorsque cela est nécessaire ; les boutons restent visibles.
- Les tableaux **Interfaces**, **Anomalies** et **Disques** affichent le
  **Type avant le Nom**, pour identifier plus facilement les composants.
- Les traductions des nouveaux textes d’interface et de démarrage sont
  complétées dans les **13 catalogues de langue** : français, anglais, allemand,
  espagnol, italien, portugais, portugais brésilien, grec, espéranto, roumain,
  russe, slovaque et turc. Le repli anglais reste disponible pour les clés manquantes.
- Les 386 clés de traduction basées sur des phrases anglaises sont remplacées
  par des identifiants stables dans les 13 langues. Les textes simples utilisent
  la clé seule ; les messages à paramètres conservent la vérification des types.

## Une interface plus réactive

Le rendu Graphviz travaille en arrière-plan. Les demandes rapprochées sont
regroupées et un rendu identique réutilise l’image et sa carte de zones cliquables.
Une ancienne demande ne peut plus remplacer le dessin d’un nouveau projet.
En cas d’échec, la dernière image valide est conservée et le diagnostic est affiché.

Ces améliorations portent sur la réactivité de l’interface et le nombre de rendus,
sans changer le fonctionnement des machines invitées.

## Des sauvegardes plus fiables

La nouvelle archive est écrite et vérifiée avant de remplacer le fichier `.mar`
précédent. Un échec avant ce remplacement conserve la dernière sauvegarde valide
et laisse le projet ouvert et marqué comme modifié.

Lorsqu’une sauvegarde est demandée avant de créer, ouvrir ou fermer un projet,
ou de quitter Marionnet, son échec bloque l’action pour préserver le travail en
cours. Les erreurs sont signalées avec leur diagnostic. Les chemins contenant
des espaces, des apostrophes ou des caractères spéciaux sont mieux pris en charge.

## Une installation fiabilisée et plus lisible

- Point d’entrée unique **`./install.sh`**, utilisable depuis la racine ou `dist/`,
  avec le moteur `.deb` par défaut et le moteur tarball via `--tarball`.
- Mode local détecté lorsqu’un binaire compilé existe dans le dépôt ;
  reconstruction lorsqu’il est absent ou périmé, et actualisation des ressources
  lors de la création du paquet local.
- Le paquet embarque ensemble l’exécutable, l’interface GTK, les icônes et les
  traductions. Cela corrige le crash **`Gpointer.Null`** causé par une ancienne
  interface conservée après installation.
- Vérification de l’interface réellement sélectionnée après installation, avec
  un diagnostic explicite si une configuration personnalisée pointe vers un
  ancien préfixe.
- Reprise et réessais des téléchargements, contrôle SHA256 et vérification des
  archives des composants de base pour détecter les fichiers tronqués.
- Dépendances du paquet All-in-One calculées à partir de ses composants,
  avec contrôle de la présence de **`libc6:i386`**. Le noyau 32 bits et ses
  bibliothèques sont vérifiés à la fin de l’installation.
- Debian Wheezy reste optionnelle et est téléchargée depuis sa version épinglée
  lorsqu’elle est nécessaire, sans téléchargement superflu pendant la construction.
- Nettoyage des anciens doublons et des scripts qui encombraient les commandes
  proposées dans le terminal.
- Affichage en **neuf étapes**, avec couleurs, durées et journal détaillé privé.
  **`--verbose`** affiche toutes les sorties en direct ; **`NO_COLOR=1`** désactive
  les couleurs. Les erreurs bloquantes et les invites de saisie restent visibles.
- Les diagnostics de la tentative réseau suivie d’un repli compatible avec
  **sudo-rs** restent dans le journal et le mode détaillé. L’affichage normal
  annonce le repli et son résultat. Les règles de droits réseau existantes
  sont conservées.

## Un démarrage plus discret

La longue bannière technique est remplacée par un message compact :

```text
MARIONNET  1.0.460
Diagnostic : marionnet --splash
```

**`marionnet --splash`** affiche la version, la révision, les dates des sources
et de compilation, OCaml et le système de construction, sans ouvrir l’interface.
**`--debug`** conserve ces informations au démarrage. **`--version`** garde sa
sortie courte, utilisée par les outils d’installation.

## Mise à jour

Depuis un clone à jour, pour installer la version publiée :

```bash
./install.sh --release 1.0.460
marionnet --version
```

Options utiles : `--local` pour construire depuis les sources, `--no-wheezy`
pour une installation sans Debian Wheezy et `--verbose` pour consulter tous
les détails. Les projets existants restent lisibles ; leur format n’est pas modifié.

## Vérifications

Les changements ont été vérifiés par la compilation, le contrôle de tous les
modules OCaml et les tests automatisés, ainsi que par des sessions GTK réelles
pour les menus, les raccourcis, l’annulation, le dessin et les dialogues.
Les tests couvrent également les sauvegardes en échec et **34 scénarios simulés
d’installation**, dont les replis réseau réussis ou bloquants, sans installation
système pendant ces simulations.
