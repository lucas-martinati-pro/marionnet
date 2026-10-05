# Chantier — fiabilisation des sauvegardes Marionnet

Ouvert le **5 octobre 2026**. Première tranche : écriture atomique du `.mar`,
signalement des échecs et protection des actions qui quittent un projet.

## Problème et résultat attendu

Le dernier fichier `.mar` enregistré doit rester utilisable tant que son remplaçant
n'est pas prêt. Un échec de sauvegarde doit laisser le projet ouvert et modifié, et
interdire une action « enregistrer puis fermer / ouvrir / créer / quitter ».

Le code de départ (`6a13753`) écrit directement sur le fichier de destination via
`tar -cSvzf`, lancé par `Log.system_or_ignore`. Ce wrapper absorbe les erreurs :
le modèle peut ensuite être enregistré comme sauvegardé alors que `tar` a échoué.
Les menus ferment leur projet après cet appel, sans contrôler son résultat.
Les chemins sont entourés d'apostrophes sans échappement, ce qui casse notamment
les fichiers nommés `TP d'aujourd'hui.mar`.

## Première tranche implémentée

`bin/project_archive.ml`, lié dans `marionnet_base`, écrit l'archive sans dépendre
de GTK et sans lancer de shell :

1. Créer un fichier temporaire privé dans le répertoire de destination.
2. Lancer GNU tar avec un tableau d'arguments : conserver gzip, les fichiers sparse
   et les exclusions existantes (`tmp`, anciens snapshots non sélectionnés).
3. Attendre le processus et refuser tout statut non nul ou terminaison par signal.
4. Vérifier la lisibilité du tar.gz avec une seconde invocation de tar.
5. Conserver les permissions du fichier précédent et synchroniser le nouveau fichier.
6. Vérifier la synchronisation du répertoire, remplacer la destination par `rename`,
   puis synchroniser le répertoire pour rendre le remplacement durable.
7. Nettoyer les fichiers temporaires, y compris lors d'un échec traité.

Les nouvelles archives sont en mode `0600`. Un lien symbolique existant reste un
lien : sa cible est mise à jour. Un lien pendant est refusé. Le remplacement atomique
exige le droit d'écriture sur le répertoire de destination, en plus de celui sur un
fichier existant. Les ACL, propriétaires et liens physiques ne sont pas reproduits
par ce remplacement ; les permissions Unix ordinaires le sont.

`bin/state.ml` marque le projet comme modifié avant toute tentative et ne le
déclare enregistré qu'après le remplacement réussi. Les erreurs de tar sont
affichées avec leur diagnostic, aussi dans les notifications du canal de contrôle.
La progression suit le fichier temporaire, puisque le `.mar` précédent ne grandit
plus pendant la sauvegarde. Les noms insérés dans les labels Pango sont échappés.
L'ouverture et le nettoyage du répertoire de travail échappent également leurs
chemins : un fichier enregistré avec une apostrophe doit pouvoir être rouvert.

Les menus Nouveau, Ouvrir, Fermer et Quitter vérifient le résultat d'une sauvegarde
demandée avant de poursuivre. Le canal `close --save` applique déjà cette règle ;
le signal « sauvegardé » est désormais fiable quand tar échoue, même si le projet
était propre avant la tentative. Le choix explicite de quitter sans enregistrer
reste disponible hors mode examen.

## Vérifications rejouables

```sh
opam exec -- dune build bin/marionnet.exe @check @runtest
xvfb-run -a bash driven-sessions/atomic-save.sh
# Même session + raccourcis GUI Fermer / Quitter, réponse Oui :
xvfb-run -a bash driven-sessions/atomic-save.sh _build/default/bin/marionnet.exe --gui
xvfb-run -a bash driven-sessions/close-save-waits.sh
xvfb-run -a bash driven-sessions/save-refused-while-running.sh
```

`test/project_archive_test.ml` exerce de vrais processus tar et une extraction
indépendante : chemins spéciaux, racine commençant par un tiret, exclusions,
permissions, remplacement, écriture partielle, sortie invalide malgré un statut 0,
processus tué, échec de vérification, source absente, échec du renommage, lien
symbolique et maintien du caractère sparse d'un disque de 16 Mio.

`driven-sessions/atomic-save.sh` provoque une écriture partielle depuis une vraie
session et vérifie : réponse d'échec et cause, identité des octets de l'ancien
fichier, projet toujours ouvert et modifié, refus de `close --save`, nettoyage,
réussite après retrait de la panne, Enregistrer sous et réouverture avec un chemin
contenant espaces, apostrophe, accent et esperluette. Le mode `--gui` témoigne
l'ouverture des questions Fermer / Quitter et une nouvelle tentative de sauvegarde
avant de contrôler que le projet est conservé ; une touche sans effet ne peut pas
constituer un succès.

**Contrôle négatif mesuré :** la session exécutée sur une compilation isolée du
code de départ échoue au premier cas de panne : l'ancien binaire répond
`{"ok":true,"saved":true,...}` après l'écriture partielle. Ce test détecte donc
le défaut original, et pas seulement la présence du nouveau module.

## Limites et suite du chantier

La protection de l'ancienne archive s'applique aux échecs **avant le renommage**.
Si la synchronisation finale du répertoire échoue après le renommage, la nouvelle
archive est déjà publiée ; le projet reste marqué modifié, car sa durabilité n'a
pas pu être confirmée. Les garanties physiques restent celles du système de fichiers.
Un arrêt non interceptable de Marionnet peut laisser un fichier temporaire voisin ;
avant le renommage, il ne remplace pas la dernière sauvegarde.

Le contrôle relit l'archive compressée : son coût dépend du volume des disques.
Il vérifie le conteneur, sans vérifier sémantiquement chaque fichier du projet.
Les garanties de lecture des anciens formats et le format v3 restent ceux de
`docs/migration-marshal-to-text.md`.

Tranches suivantes, à traiter séparément :

- Rendre **Enregistrer sous** transactionnel aussi pour le nom du projet et son
  répertoire de travail : restaurer leur identité précédente si l'écriture échoue.
- Sérialiser les opérations concurrentes de sauvegarde / renommage / fermeture et
  vérifier la cohérence du snapshot quand le modèle change pendant l'opération.
- Définir la récupération des temporaires laissés par un arrêt brutal, puis tester
  l'interruption de Marionnet lui-même et les volumes réseau ou particuliers.
- Mesurer le coût de vérification sur de gros TP et améliorer la progression en
  fonction de ces mesures.
