# Marionnet @VERSION@ — Des formulaires plus lisibles et des erreurs plus utiles

Cette version améliore la configuration des équipements, les diagnostics et la
réactivité du dessin. Elle fiabilise également l’arrêt et le redémarrage des
composants.

## Des formulaires mieux organisés

- Les champs **Nom** et **Étiquette** sont regroupés dans un en-tête plus compact.
  Une indication précise que l’étiquette est facultative.
- Les champs de saisie et les listes déroulantes utilisent mieux la largeur
  disponible ; les libellés restent lisibles et les sections sont plus distinctes.
- Des marges séparent les boutons **Modifier / Importer**, les options des services
  du routeur et les boutons **Aide / Annuler / Valider**.
- Les titres de section utilisent la couleur du thème GTK.
- Les noms invalides ou déjà utilisés sont signalés directement dans le formulaire.
- Les paramètres profitent de la hauteur disponible ; sur un petit écran, le
  contenu peut défiler et les boutons de validation restent accessibles.
- L’indication d’étiquette facultative est traduite dans les **13 langues** disponibles.

## Des messages d’erreur qui aident à agir

Les erreurs d’ouverture, de sauvegarde, d’export, de rendu, d’annulation et de
fonctionnement des composants présentent un message compréhensible et, lorsque
la cause est identifiée, une piste de résolution : permissions insuffisantes,
fichier absent, disque plein ou système de fichiers en lecture seule.

Les détails techniques sont regroupés dans une zone dépliable et défilante.
Un bouton permet de **copier le rapport** pour faciliter le diagnostic. Ces
nouveaux messages sont traduits dans les **13 langues** de Marionnet.

Une sauvegarde en échec conserve la sauvegarde précédente et laisse le projet
marqué comme modifié. Si le rendu du dessin échoue, la dernière image valide
reste affichée.

## Un dessin qui réagit plus vite

Le délai de regroupement des demandes de dessin passe de **120 ms à 16 ms**.
Le recalcul démarre donc plus rapidement après l’ajout, la suppression ou la
modification d’un équipement. Le temps de calcul de Graphviz dépend toujours
de la taille du réseau.

## Des arrêts et redémarrages plus fiables

Le redémarrage attend désormais la fin effective des processus du composant,
avec une attente bornée, au lieu d’imposer une pause fixe de sept secondes.
La gestion des erreurs de démarrage et de terminaison est également renforcée.

## Une version publiée retrouvée dans les sources

Après une publication réussie, le workflow enregistre le numéro de version
publié dans **META** sur la branche principale. Un `git pull` permet ainsi de
récupérer ce numéro pour les prochaines constructions locales.

## Mise à jour

Pour installer cette version publiée :

```bash
./install.sh --release @VERSION@
marionnet --version
```

Pour construire depuis les sources à jour :

```bash
git pull
./install.sh --local
```

Le format des projets reste inchangé.

## Vérifications

Compilation, contrôle de l’ensemble des modules OCaml et tests automatisés.
Des sessions GTK réelles vérifient les formulaires sur petit et grand écran,
les raccourcis d’annulation, les erreurs de sauvegarde et de rendu ainsi que
la copie des rapports. Les tests de processus couvrent également les attentes
de terminaison et le cycle de vie d’un concentrateur.
