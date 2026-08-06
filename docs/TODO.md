# TODO — améliorations repérées, pas encore planifiées

Liste **transverse** : ce qui mérite d'être fait mais n'appartient à aucun chantier en cours, ou
n'y entre que de biais. Ce qui relève d'un chantier reste dans son document (`docs/*.md`, section
« Reste au chantier ») — ici, seulement ce qui serait sinon perdu.

Chaque entrée dit : le **défaut constaté**, ce qu'on **veut à la place**, et ce que
l'implémentation devra affronter (pour que la reprise ne recommence pas l'analyse).

---

## GUI — griser « Enregistrer » / « Enregistrer sous » quand quelque chose tourne

**Constat.** Ces entrées restent actives alors que la sauvegarde est refusée dès que
`st#is_there_something_on_or_sleeping ()` est vrai (`gui_menubar_MARIONNET.ml:160,186,227`). Pour
« Enregistrer sous », l'utilisateur est donc invité à **choisir un nom de fichier**, puis
l'opération est refusée par un dialogue d'erreur (`Msg.error_saving_while_something_up`) : on
l'engage dans une action pour la lui refuser ensuite.

**Voulu.** Que ces entrées soient **insensibles** (grisées) tant que quelque chose est allumé ou
suspendu — l'interdit se lit alors *avant* le geste, comme pour les autres entrées conditionnelles
de la barre de menus. Concerne au moins « Enregistrer », « Enregistrer sous » et « Copier vers »
(les trois sites ci-dessus).

**Ce que l'implémentation devra affronter.** Le mécanisme de sensibilité réactive existe déjà :
piles `sensitive_when_Active` / `_Runnable` / `_NoActive` (`state.ml:260-269`), alimentées par des
réactions `Cortex` dans `motherboard_builder.ml` — il suffirait d'une quatrième pile. Le point dur
est ailleurs : ces réactions se branchent sur des `Cortex` (`project_paths#filename`,
`network#nodes`, `network#cables`), or **l'état allumé/suspendu des composants n'est porté par
aucun `Cortex`** — `is_there_something_on_or_sleeping` interroge la liste des nœuds à chaud. Il
faut donc une **source de notification** aux transitions ; les points naturels sont les
`*_right_now` de `user_level.ml`, où le chantier `marionnet-automate-composants` (épisode 3) a déjà
placé les `Sketch.refresh_sketch ()` explicites de fin de transition.

*Repéré le 2026-08-01, à l'occasion du rejeu GUI du journal 22.*

---

## Modèle — le renommage d'un composant n'est pas atomique

**Constat.** `User_level.virtual_machine_with_history_and_ifconfig#update_virtual_machine_with`
(`user_level.ml:1418-1425`) renomme les entrées **ifconfig** et **history**, renomme le
**répertoire hostfs**, puis rend la main ; c'est seulement ensuite que `update_with` appelle
`set_name`, dont le `check_name` (`user_level.ml:520-523`) **peut refuser** le nom. Un nom
mal formé produit donc un composant qui garde l'ancien nom pendant que ses lignes de treeview et
son répertoire portent le nouveau — l'orphelin silencieux qu'on cherche partout à éviter.
Mesuré le 2026-08-06 (chantier `marionnet-pilotage-par-script`, ép. 4d-2b) : après un `rename m1
1m` refusé, la ligne ifconfig de `m1` s'appelait `1m`, et l'opération suivante sur ses ports
échouait sur *« unique_row_id_such_that: there were 0 results instead of 1 »*.

**Pourquoi ce n'est pas un bug observable aujourd'hui.** Les deux seuls appelants valident en
amont : la GUI par `Gui_bricks.Ok_callback.check_name` (identifiant **puis** unicité, avant
d'appeler `update_<kind>_with`) et, depuis l'ép. 4d-2b, le serveur de contrôle par les deux mêmes
tests. C'est une **fragilité** — la garde vit chez les appelants, dupliquée, et un troisième
appelant l'oubliera.

**Voulu.** Que le modèle valide **avant d'écrire** : `update_virtual_machine_with` (et, tant qu'à
faire, `update_structural_with`) rejetant un nom mal formé ou déjà pris **sans avoir rien touché**.
Les appelants pourraient alors se contenter de rapporter l'erreur.

**Ce que l'implémentation devra affronter.** `check_name` est un `let` **local** au corps de
`component` (`user_level.ml:520`), donc non appelable de l'extérieur : il faut soit l'exposer, soit
appeler directement `StrExtra.Class.identifierp`. L'unicité, elle, appartient au réseau
(`network#name_exists`, `user_level.ml:1830`) et n'est testée qu'à l'ajout
(`network#add_node`) — un renommage n'y passe pas. Attention enfin à ne pas déplacer la validation
*dans* `set_name` : elle y est déjà, c'est bien **son heure** qui est trop tardive.

*Repéré le 2026-08-06, par le banc de l'épisode 4d-2b.*
