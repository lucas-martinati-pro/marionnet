# Première modernisation de l’utilisation

Cette étape concerne l’espace de travail GTK et le rendu du réseau. Le changement
sur les droits réseau du commit `2f2ae38` a été annulé par `0e72783` à la demande
de l’utilisateur. Aucun changement de règle sudoers n’entre dans cette étape.

## Utilisation

- Nouveau, Ouvrir et Enregistrer sont accessibles dans le menu Projet. Les
  menus sont réunis dans la barre de titre native GTK, sans seconde barre de
  boutons. Les contraintes de sauvegarde et de mode examen restent appliquées.
- `Ctrl+N`, `Ctrl+O` et `Ctrl+S` correspondent à ces actions et sont affichés
  dans le menu. Les anciens
  raccourcis d’ajout de switch et de pont NAT qui les interceptaient sont retirés.
- Le nom du projet reste visible dans la barre de titre. Une pastille `•` le
  précède uniquement lorsque des modifications ne sont pas enregistrées ;
  l’état détaillé reste accessible en infobulle. Le titre natif devient
  `• Marionnet - fichier.mar`, puis `Marionnet - fichier.mar` après sauvegarde.
  Le statut utilise
  le prédicat de sauvegarde existant, y compris les changements des treeviews.
- La palette affiche par défaut uniquement les icônes de 32 pixels, avec leurs
  infobulles. La bascule « Aa » affiche ou masque les noms des composants sans
  modifier le projet ni reconstruire ses menus. Les onglets utilisent du texte
  droit et l’espace vide explique comment commencer.
- La fenêtre choisit une taille adaptée à l’écran. Les tableaux larges utilisent
  le défilement horizontal et la barre de réglage du dessin défile verticalement.
- Les actions collectives suivent les possibilités actuelles du modèle. Les
  compteurs de composants, de câbles et de composants actifs sont visibles en bas.
- Les nouveaux textes sont traduits en français et en anglais. Les autres
  langues utilisent le repli anglais existant.

## Rendu

Les demandes rapprochées sont regroupées sur 120 ms. Un seul rendu travaille à
la fois ; la demande en attente est remplacée par la plus récente. Quand le DOT,
les options et la destination sont identiques au dernier rendu réussi, aucun
nouveau processus Graphviz n’est lancé.

Le modèle est lu dans le thread GTK pour produire un instantané immuable. Seul
Graphviz travaille hors de ce thread. Ses fichiers d’entrée, de sortie et de
diagnostic sont temporaires ; le programme reçoit ses arguments séparément,
sans commande shell contenant le chemin du projet. Un échec conserve le dernier
PNG réussi et affiche le diagnostic. Graphviz passe par le thread de lancement
permanent existant, avec le signal de mort du parent utilisé par l’application.
La génération de demande et le chemin du
projet sont vérifiés avant publication : un ancien rendu est abandonné après
une nouvelle demande ou une fermeture.

Cette étape ne remplace pas le PNG par un éditeur de graphe interactif. La
navigation, les dialogues de composants et les mécanismes de simulation restent
ceux de l’application. L’optimisation mesurée porte sur le nombre de rendus et
sur la réponse de GTK pendant le travail de Graphviz, pas sur la vitesse des
machines invitées.

## Vérification

```sh
opam exec -- dune build @install @check @runtest
xvfb-run -a python3 driven-sessions/workspace.py
xvfb-run -a bash driven-sessions/atomic-save.sh _build/default/bin/marionnet.exe --gui
bash driven-sessions/main-window-height-bounded.sh _build/default/bin/marionnet.exe
```

Le test OCaml utilise le vrai Graphviz : rendu, publication différée, chemin
contenant des caractères spéciaux, erreur de syntaxe, résultat abandonné et
nettoyage. Le banc GTK utilise une vraie application avec deux hubs et un câble,
sans démarrer d’invité et sans commande privilégiée. Il exerce les trois
raccourcis et les trois entrées du menu Projet, la bascule des libellés et les
menus des composants dans les deux modes, les titres enregistré/modifié, le cache, une
rafale de douze modifications, un Graphviz bloqué, un échec après écriture
partielle, une reprise et un changement de projet pendant un rendu.

Les essais sur des écrans de 800 × 600 et 1280 × 900 passent. Une rafale de douze
modifications pendant un rendu bloqué ne lance que deux processus Graphviz
(l’ancien et le dernier). Cinq demandes identiques ne lancent aucun nouveau
processus. Le banc avec quarante machines confirme que la visite des tableaux
ne fait pas grandir la fenêtre au-delà de l’écran.

Pour conserver les captures du banc :

```sh
xvfb-run -a -s '-screen 0 1280x900x24' python3 driven-sessions/workspace.py \
  --screenshots /tmp/marionnet-workspace-preview
```

Pour lancer la version construite sans installation système :

```sh
_build/default/bin/marionnet.exe
```
