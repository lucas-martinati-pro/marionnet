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

## Correction du paquet installé — 5 octobre 2026

Le lancement après `./install.sh` échouait avec `Gpointer.Null` dans
`Gui.window_MARIONNET` : le paquet All-in-One remplaçait le binaire de sa couche
applicative historique, mais conservait son ancien Glade. Le nouveau binaire
cherchait donc des widgets absents. Les traductions JSON étaient également
absentes du paquet installé ; un essai depuis le dépôt masquait ces défauts.

La construction locale passe maintenant par `dune build @install` puis par une
installation Dune temporaire sous `/usr`. Elle fusionne l'exécutable et ses
ressources déclarées avec les couches d'images invitées et de noyaux. Le build
est actualisé même si le numéro de version n'a pas changé. L'installeur vérifie
ensuite le Glade réellement sélectionné par `marionnet --paths` : un ancien
`MARIONNET_PREFIX` conservé dans une configuration personnalisée entraîne un
diagnostic explicite plutôt qu'une fausse annonce de réussite. Les droits réseau
ne sont pas modifiés par cette correction.

Le nouveau banc extrait le vrai paquet, compare ses ressources à celles du
dépôt et joue les menus, les raccourcis, la palette, les titres et le rendu avec
le binaire extrait, depuis un répertoire extérieur au dépôt. Il n'installe rien
sur le système et ne démarre aucun invité :

```sh
bash dist/build-all-in-one.sh
python3 driven-sessions/installed-workspace.py dist/marionnet-all-in-one_1.0.459_amd64.deb
```

Sur la machine ayant signalé le défaut, le préfixe effectif pointait encore
vers `/usr/local/share/marionnet`. La réparation utilise les ressources
du paquet sous `/usr/share/marionnet`, tout en conservant explicitement les
chemins existants des images et noyaux sous `/usr/local/share/marionnet`. Une
copie des configurations système et utilisateur originales est gardée avant
cette adaptation ; le préfixe effectif est contrôlé avec `marionnet --paths`.

## Annuler et rétablir les modifications du réseau

Le menu Édition propose Annuler (`Ctrl+Z`) et Rétablir (`Ctrl+Y`, également
`Ctrl+Maj+Z`). Il conserve les trente dernières modifications effectuées par les
actions d'ajout, de propriétés et de suppression, ainsi que par leurs équivalents
du canal de contrôle. Une nouvelle modification abandonne la branche de
rétablissement ; changer de projet vide l'historique. Revenir à la configuration
sauvegardée retire la pastille de modification.

Cette première étape agit sur un réseau arrêté. Elle restaure la topologie, les
paramètres des composants, les tables associées et les scripts de démarrage.
Les démarrages/arrêts et les modifications directes des cellules des tableaux
n'entrent pas dans l'historique : si ces dernières ont changé les données depuis
l'édition enregistrée, l'annulation refuse de les écraser et réinitialise son
historique. Les restrictions du mode examen restent vérifiées.

Les fichiers supprimés avec un composant sont retenus par des liens physiques
privés dans `tmp/`, sans copie des gros fichiers COW ni restauration d'anciens
contenus de disques. Les scripts de démarrage sont conservés en mémoire. Les
états et journaux restent associés au composant restauré. La restauration attend
les tâches de simulation hors du thread GTK ; un échec tente de rétablir le
réseau courant et affiche son diagnostic. Les fichiers d'historique sont exclus
des archives `.mar`.

Vérification : `opam exec -- dune build @install @check @runtest`, puis
`xvfb-run -a python3 driven-sessions/undo.py`. Le banc GTK exerce les vrais
raccourcis, les renommages avec câbles, suppression/rétablissement, la branche
abandonnée et la restauration des fichiers d'une machine. Le test de fichiers
exerce un vrai disque sparse, ses inodes et dates, un lien symbolique et un
répertoire en lecture seule.
