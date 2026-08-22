# TODO — améliorations repérées, pas encore planifiées

Liste **transverse** : ce qui mérite d'être fait mais n'appartient à aucun chantier en cours, ou
n'y entre que de biais. Ce qui relève d'un chantier reste dans son document (`docs/*.md`, section
« Reste au chantier ») — ici, seulement ce qui serait sinon perdu.

Chaque entrée dit : le **défaut constaté**, ce qu'on **veut à la place**, et ce que
l'implémentation devra affronter (pour que la reprise ne recommence pas l'analyse).

---

## Idée — **composer** deux projets (importer un `.mar` dans le projet courant)

**Constat.** Il n'existe aucun moyen, ni en GUI ni ailleurs, de verser le contenu d'un projet dans
un autre : ouvrir un `.mar` **remplace** le projet courant. Un enseignant qui a préparé un « bloc
LAN » et un « bloc routage » ne peut pas les réunir autrement qu'en recréant les composants à la
main dans l'un des deux.

**Voulu.** Un import additif : les nœuds et câbles du projet importé s'ajoutent à ceux du projet
courant, avec leurs configurations (treeviews comprises), sous un préfixe ou un plan de renommage
explicite en cas de collision.

**Ce que l'implémentation devra affronter.** C'est plus qu'une commande — et c'est pourquoi ce
n'est **pas** un épisode du chantier `pilotage-par-script`, qui l'a examiné et écarté (§ 4.8,
ép. 4g) : le contrat de ce canal est « les mêmes possibilités et limites que la GUI », or la GUI ne
compose pas. Les obstacles réels, dans l'ordre : (a) les **collisions de noms** (`name_exists`
n'offre qu'un refus, il faut une politique de renommage, or renommer touche ifconfig, defects,
history et le répertoire `hostfs/`) ; (b) `netmodel/network.xml` ne porte **que** nœuds et câbles —
les treeviews sont persistées à part (`states/…`) et devraient être fusionnées ligne à ligne ;
(c) les répertoires `hostfs/<nom>/` et les états de disque à recopier ; (d) les remaps d'import
(`remap_obsolete_kernel_at_import`, `remap_absent_distrib_at_import`) à rejouer sur la partie
importée seulement. Une fois cela fait, l'exposer au canal serait trivial (une commande de plus).

*Idée issue de la voie (a) de `forest`, écartée le 2026-08-07 (ép. 4g de `pilotage-par-script`) :
gardée ici parce qu'elle a une valeur pédagogique propre, indépendante du scripting.*

---

## Bancs — le `cleanup` d'un banc versionné ne tue pas la session qu'il a lancée

**Constat** (mesuré le 2026-08-22 par l'épisode 27 de `marionnet-todo-transverse`, en jouant ses
bancs jetables sur le patron des bancs versionnés). Le patron est

```bash
timeout -k 5 300 "$BIN" --debug --control-socket "$sock" >/dev/null 2>"$stderr" &
pid=$!            # <-- le pid de `timeout', PAS celui de Marionnet
```

et le `cleanup` fait ensuite `kill -9 "$pid"`. `timeout` relaie les signaux qu'il **peut**
intercepter ; SIGKILL n'en fait pas partie : le relais meurt, la session lui survit. Mesuré : une
session tuée de cette façon était encore vivante **266 s** plus tard, avec son invité UML
`linux-6.12.95` et la douzaine de processus de celui-ci — jusqu'à ce qu'on la tue par son vrai pid.

**Conséquence.** Un banc interrompu (ou dont un cas échoue avant le `quit` du canal) laisse tourner
une session **complète** jusqu'à l'expiration de son propre `timeout`, soit 300 à 900 s selon le
banc, et le run suivant hérite de ses orphelins. C'est exactement le genre de résidu qui a fait
naître l'entrée « un invité vivant n'a aucune socket mconsole » (écrite par l'ép. 20, soldée par
l'ép. 27 : le processus qu'on croyait vivant était la poussière d'un invité mort).

**Voulu.** Que le `cleanup` d'un banc tue la **session**, et que le `timeout` reste ce qu'il est :
un garde-fou de durée, pas un mandataire.

**Ce que l'implémentation devra affronter.** Le vrai pid est **publié par le canal** depuis
l'épisode 18 : `status` (comme `quit`) le renvoie dans son JSON, donc un banc peut le lire une fois
la socket ouverte et le garder à côté du pid de `timeout`. Restent deux cas : (a) une session qui
meurt **avant** d'ouvrir son canal n'a pas de pid à publier — il faut alors s'en remettre au pid de
`timeout` comme aujourd'hui, ce qui suffit puisqu'il n'y a rien à tuer ; (b) `timeout --foreground`
(ou un `setsid` + `kill -- -<pgid>`) tuerait le groupe entier, mais c'est un kill **large**, contre
la discipline du dépôt (tuer par pid exact, liste affichée d'abord). 13 des 19 bancs versionnés
portent le patron.

*Repéré le 2026-08-22 par l'épisode 27 de `marionnet-todo-transverse`, qui l'a mesuré sans le
corriger (règle du chantier : un défaut voisin s'écrit, il ne se corrige pas en passant).*
