---
name: marionnet-triage-binaires
description: Triage des binaires d'une image invitée Marionnet — la passe de DÉCISION (lire un rapport de sonde, en tirer un diff de politique) et le rituel des trois étages (sonder / décider une fois / appliquer). Charger avant de sonder une image invitée, avant de juger un rapport de `docs/probe-reports/`, avant d'écrire ou de modifier une ligne de `binary_policy.<distrib>.tsv`, ou quand une image neuve vient d'être construite et qu'il faut savoir si ses binaires fonctionnent.
---

# Triage des binaires d'une image invitée

> Objectif du dispositif : **une image invitée construite ne contient que des binaires qui
> fonctionnent**, et le constat se refait sans rouvrir de chantier. Conception, mesures et
> journal : `docs/triage-binaires-image-invitee.md` (§ 3 = les étages, § 4 = la politique,
> § 5 = les applicateurs). **Ce skill ne recopie ni la grammaire des scripts ni la politique** :
> il porte le *jugement* et les *interdits*. Pour la grammaire, `--help` du script.

## Les trois étages, et où tu te tiens

| étage | qui | quoi |
|---|---|---|
| 1 — sonder | `make filesystem.probe-image-binaries IMAGE=…` | un boot, toutes les sondes ⇒ un rapport TSV dans `docs/probe-reports/` |
| 2 — **décider** | **toi, une fois** | lire le rapport ⇒ proposer un **diff** de `binary_policy.<distrib>.tsv` |
| 3a — appliquer (image publiée) | `make filesystem.apply-binary-policy IMAGE=…` | traduit la politique en commandes jouées dans l'invité |
| 3b — appliquer (construction) | `apply_binary_policy` de `uml/pupisto.debian.sh` | les mêmes jugements dans le chroot, avant `clean_debian_filesystem` |

**Tu es ENTRE la sonde et la politique, jamais dans la boucle.** Tu ne touches ni l'image ni
les scripts pendant une passe : ton seul livrable est un diff de TSV que l'humain valide et
commite. Les deux cibles n'exposent que `IMAGE=` ; tout le reste passe par `OPTIONS=`.

## La passe de décision

1. **Prendre le rapport entier**, pas seulement les lignes en échec. Les colonnes sont
   `name verdict rc probe via <première ligne du message>` ; l'en-tête nomme l'image, son `sum`
   et le **serveur X** qui a servi — un verdict X est une propriété du **couple (image, serveur)**.
2. **Relire aussi les `OK`.** C'est là qu'on a trouvé 33 binaires qui ne démarraient pas (ép. 3),
   puis 7 de plus (ép. 4) : `rc` 1 est le statut d'un outil qui imprime son usage *et* celui d'un
   lanceur cassé.
3. **Pour chaque cas, la question de l'épisode 6** — la seule qui décide d'un `drop` :
   **« le paquet P qui porte ce binaire a-t-il encore un intérêt sans lui ? »**
   - non ⇒ l'action retire **le paquet**, et on **repose la question à chaque maillon** de la
     chaîne de dépendances (qui l'a tiré ? ce parent sert-il encore ?) ;
   - oui ⇒ le paquet reste, l'action est un `rm -f /usr/bin/<nom>`.
   Les paquets se **nomment** dans l'action. **Jamais d'`autoremove`** : ce qui disparaît est écrit.
4. **Écrire une ligne par cas examiné** — `ignore` compris. La politique ne porte que des
   *exceptions* (`keep` est le défaut, non écrit : 225 lignes pour 2060 candidats), mais un cas
   jugé sans ligne se **re-juge à chaque image**, ce que le gel doit éviter.
5. **Chaque ligne est adossée à une preuve du rapport**, et la colonne `reason` la dit. Les
   familles sont des **en-têtes de groupe** (`# --- qt5-wrapper (47)`), pas une 5ᵉ colonne : elles
   disent **sur quoi** le verdict a été lu, donc ce qu'un humain peut contester.

## Les interdits (payés par la mesure)

- **Une sonde ne publie JAMAIS.** Elle travaille dans un COW jetable : le nom d'une image *est*
  son `sum`, donc sonder ne doit produire aucune image.
- **Republier une image, c'est la renommer.** Une image dont le contenu change se republie sous
  un autre nom ; le publieur refuse un `mtime` qui a dérivé plutôt que de le réparer.
- **Une image publiée ne se reprend pas pour le principe** (critère de l'ép. 7) : on la
  reconstruit quand un binaire **du périmètre du TP** est cassé, pas pour un `qmake` mort.
  16341 est volontairement laissée en l'état, et la politique décrit un état **voulu**.
- **Un verdict gelé ne se re-dérive pas.** Sans le gel, chaque passage coûterait des tokens *et
  pourrait décider autrement*.
- **Une action de politique se MESURE dans l'invité avant d'être appliquée.** L'étage 3a **sans
  options écrit une nouvelle image** dans le répertoire de release : les deux répétitions sont
  `OPTIONS=--dry-run` (ne boote rien) puis `OPTIONS=--measure` (joue les commandes dans l'invité,
  n'exporte rien — il relaie `--no-export`). C'est cette mesure qui a réfuté l'action de l'ép. 3.
- **Une cause structurelle se vérifie par la STRUCTURE, jamais par le motif du message.**
  Compter les liens possédés moins les cibles existantes a trouvé 7 cassés qu'une relecture par
  motif avait manqués ; et un `RUNPATH` d'exécutable ne couvre pas les dépendances
  **transitives** — la lib « absente » peut être sur le disque.
- **Un `rc` ne dit pas si le binaire a démarré ; le MESSAGE le dit.** D'où le verdict `BROKEN`,
  lu sur le message et posé avant l'échelle.
- **« Est-ce une application X ? » se mesure** (fermeture transitive vers `libX11`), jamais ne
  se lit dans une liste écrite à la main — une liste blanche se périme. La sur-approximation est
  du bon côté : un faux positif se classe `ignore` une fois, un faux négatif laisse passer une
  application graphique sans jugement.
- **Le format à 4 colonnes n'a qu'UN lecteur**, l'étage 3a. `pupisto` lui **demande** les actions
  (`--print-actions`) au lieu de reparser : un second lecteur serait libre de diverger.
- **`/loop` est refusé** : chaque itération paierait un boot complet. *Un boot, toutes les sondes.*

## Une image neuve vient d'être construite

La sonder, comparer le rapport à la politique de sa distribution, et ne juger **que ce qui est
nouveau** : les `drop` doivent être absents de sa `BINARY_LIST`, et les `fix` avoir mis le module
là où le script le cherche. Une distribution **sans** politique n'est pas une faute (3b dit
*nothing to apply* et rend 0) : la politique est **par distribution**, trixie d'abord.

## Hors périmètre (tranché, ne pas rouvrir ici)

L'**amaigrissement** de l'image (viser la place vise des paquets, pas des binaires — autre
chantier), la **réparation du relais X** `bin/x.ml` (ce dispositif le constate et le nomme), et
les binaires cassés par le **serveur X de l'hôte** (le constat fondateur du chantier était de
ceux-là : `xlinks2` marche ici).
