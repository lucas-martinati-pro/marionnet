# Marionnet @VERSION@ — Consoles plus lisibles et opérations plus fiables

Cette version améliore les consoles des machines virtuelles, les mises à jour
et la gestion des opérations en arrière-plan.

## Consoles des machines virtuelles

- Police monospace lissée et thème sombre contrasté, avec des marges.
- Taille initiale compacte de **8 points**, sans barre de défilement, pour
  garder plusieurs consoles à l’écran.
- Zoom avec **Ctrl + / Ctrl −** ou **Ctrl + molette** ; **Ctrl + 0** rétablit
  la taille initiale.
- Taille initiale personnalisable entre 6 et 32 points avec
  `MARIONNET_TERMINAL_FONT_SIZE` dans `~/.marionnet/marionnet.conf`.
- Historique de 10 000 lignes, accessible avec **Maj + Page précédente / suivante**.
- Le copier-coller **Ctrl + Maj + C / V** et l’interruption **Ctrl + C** sont conservés.

Ces réglages concernent les consoles xterm et uxterm ouvertes par Marionnet.

## Mises à jour

- Affichage plus compact : progression en trois étapes, journal détaillé privé
  et erreurs plus visibles ; l’option `--verbose` affiche les détails.
- Vérification du **SHA256** du paquet avant son installation : un paquet
  incomplet ou dont l’empreinte est incorrecte est refusé.
- Chaque paquet Tout-en-un reçoit un identifiant de construction. Après
  installation de cette version, un paquet republié sous le même numéro de
  version pourra également déclencher une proposition de mise à jour.
- Le workflow publie cet identifiant avec le paquet et conserve la synchronisation
  du numéro de version dans `META` après publication.

Les versions antérieures doivent d’abord installer cette version pour recevoir
la détection des nouvelles constructions.

## Opérations en arrière-plan et réactivité

- Coordination de l’ouverture, des sauvegardes et des opérations sur les
  équipements, avec transmission des changements GTK au thread principal.
- Affichage des opérations en cours et protection contre les demandes en double.
- Rafraîchissements plus ciblés des tableaux et réutilisation du dessin lorsque
  son contenu n’a pas changé.
- Mesures séparées du calcul Graphviz, du chargement de l’image et des mises à
  jour des tableaux pour faciliter le diagnostic des lenteurs.
- Comportement plus cohérent du clavier dans les formulaires : focus initial,
  validation, annulation et aide.

## Installation

Depuis une installation existante, utilisez la proposition de mise à jour de
Marionnet ou :

```bash
marionnet-update
```

Depuis le dépôt :

```bash
git pull
./install.sh --release @VERSION@
```

Le format des projets reste inchangé.

## Vérifications

Compilation, contrôle de tous les modules OCaml et tests automatisés, avec des
sessions GTK pour les opérations et les formulaires. Le zoom, le retour à la
police initiale, le copier-coller et Ctrl + C ont été vérifiés dans de vrais
xterm et uxterm. Les tests de mise à jour couvrent les empreintes incorrectes,
les nouvelles constructions à version identique, les erreurs réseau et
l’absence de nouvelle proposition après installation du même paquet.
