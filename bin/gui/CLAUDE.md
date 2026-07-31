# bin/gui/ — complétion GTK

Patron : `gui_glade3.xml` (source de vérité de l'interface, éditer avec `make edit-gui`) →
`bin/gui.ml` (accès typés aux widgets) → les modules d'ici **finissent** l'interface par code.
La plupart sont des foncteurs `Make (State : sig val st : State.globalState end)` appliqués
dans `bin/marionnet.ml` — c'est l'injection de l'état global dans la GUI.

**Piège majeur** : `bin/gui.ml` a été généré par lablgladecc **puis modifié à la main**.
Aucune procédure de régénération n'est établie → ne JAMAIS relancer lablgladecc sur
`gui_glade3.xml` pour remplacer `gui.ml` ; éditer `gui.ml` à la main en cohérence avec le xml.

Discipline threads : GTK depuis le seul thread principal ; depuis un autre thread, passer par
`bin/gMain_actor.ml`. Workaround lablgtk connu : `~label:""` obligatoire dans
`GMenu.image_menu_item` (cf. gui_toolbar_COMPONENTS_layouts).

## Où l'utilisateur agit (à savoir avant de scénariser un test GUI)

**Le dessin du réseau n'est PAS interactif.** C'est un PNG produit par graphviz : il affranchit
l'utilisateur de dessiner son réseau, rien de plus. Pas de clic droit sur un composant, pas de
menu contextuel — un scénario de test qui suppose le contraire est infaisable.

- **Barre verticale GAUCHE** = palette des composants et **seul** point d'action par composant.
  L'enchaînement est : icône du **type** de composant (machine, routeur, hub…) → **action**
  (démarrer, suspendre, reprendre, arrêter…) → **choix du composant** cible. C'est l'ordre
  action-puis-objet, l'inverse de ce qu'on attend d'un menu contextuel.
- **Barre horizontale BASSE** = actions **collectives** (« Tout démarrer », « Tout éteindre »
  brutalement…). Certaines actions n'existent QUE là : l'extinction brutale d'**un seul**
  composant n'est pas proposée par la palette, seul le « Tout éteindre » collectif la déclenche.
- **Barre verticale DROITE** = options dot (rendu du dessin). C'est là que se trouve
  l'interactivité liée au dessin, pas dans le PNG.

Rôles des fichiers : voir `CLAUDE-file-overview.md`.
Chantier GUI : charger le skill `marionnet-gui`.
