# Chantier : modernisation-world-bridge

> Chantier long, ouvert le 2026-07-18. Cible : le composant **`world_bridge`**
> (`bin/world_bridge.ml`, dernier bouton de la palette gauche, icône planète), qui
> raccorde le réseau virtuel au **vrai réseau L2 de l'hôte**. Deux axes : (1) éliminer
> sa **barrière de mise en œuvre** (config hôte manuelle hors GUI), sur le modèle du
> chantier `daemon-elimination` ; (2) un **travail GUI** rendant le composant
> compréhensible pour enseignants et étudiants. Skill de pilotage : `chantier-long`.

## 1. Contexte et objectif

`world_bridge` est le **seul composant qui rompt le bac à sable** : tous les autres
équipements (y compris `world_gateway`, NAT `slirpvde` auto-suffisant) sont des processus
purement virtuels sans contact avec le vrai réseau. `world_bridge`, lui, crée un *tap* via
`Tap_provider` (sudo scoped + iproute2, hérité de `daemon-elimination` ép. 3) et l'attache
à un **bridge Linux préexistant côté hôte** (`MARIONNET_BRIDGE`, `marionnet.conf`), puis
relie ce tap à l'unique hublet du composant par un `vde_switch` 2 ports en mode *hub*.

Deux usages (help `bin/world_bridge.ml`, `Dialog_add_or_update.help_callback`) :

1. **Accès L2 *bridgé* au vrai LAN/Internet** : les VM obtiennent de vraies IP sur le vrai
   sous-réseau et voient les **vrais services** (DHCP, DNS, NFS…).
2. **Lab distribué multi-machines** : relier des instances Marionnet tournant sur des
   **postes physiques différents** en un même domaine de diffusion — son *killer feature*
   pédagogique, sans substitut.

### Le problème — deux frictions

- **Barrière de mise en œuvre.** Rien n'est *self-service*. L'admin doit, **à la main et
  hors GUI** : (a) créer le bridge hôte `MARIONNET_BRIDGE`, (b) **y asservir la carte
  physique** (`eth0`), (c) **migrer l'IP de l'hôte sur le bridge**. `daemon-elimination` a
  déjà supprimé le *daemon root* pour la création du tap (`Tap_provider`), mais **pas** ces
  trois gestes hôte — c'est la barrière résiduelle. Note critique : (b)+(c) sont
  **destructeurs** — asservir la carte primaire d'un vrai poste peut **couper la
  connectivité de l'hôte** en cours de route. C'est précisément *pourquoi* c'est resté
  manuel.
- **Opacité GUI.** Deux composants « monde » côte à côte (`world_bridge`, `world_gateway`)
  prêtent à confusion ; le texte d'aide est daté (« ethernet socket », `ifconfig/route`,
  renvoi wiki) ; l'étudiant ne sait pas *lequel* choisir ni *pourquoi* l'un « ne marche
  pas » sans préparation hôte.

### Objectif du chantier

Rendre `world_bridge` **utilisable sans préparation hôte manuelle risquée** (axe barrière)
et **compréhensible dans la GUI** (axe pédagogique), sans dégrader ses deux usages ni la
surface de sécurité obtenue par `daemon-elimination`.

## 2. Axe A — élimination de la barrière de mise en œuvre

Principe repris de `daemon-elimination` : ce qui était une **action admin permanente et
hors-bande** doit devenir un **provisionnement runtime, scoped et réversible** (sudo étroit +
iproute2), ou disparaître. Ici la difficulté nouvelle vs le daemon : l'un des gestes à
automatiser (asservir la carte de l'hôte) est intrinsèquement **dangereux**.

### 2.1 Options évaluées

| # | Solution | Sémantique | Barrière | Risque hôte | Complexité | Verdict |
|---|---|---|---|---|---|---|
| A | **NAT bridge privé auto** (bridge dédié `mnbr0` + IP côté hôte + `iptables -t nat MASQUERADE` sur la sortie, +`dnsmasq` DHCP optionnel) | NAT (VM derrière l'hôte, pas sur le vrai LAN) | **quasi nulle** (tout créé par Marionnet) | **nul** (ne touche pas la carte de l'hôte) | moyenne | **retenu — défaut** |
| B | **L2 réel auto** (détecter la carte route-défaut, l'asservir au bridge, migrer l'IP, rollback à la sortie) | L2 fidèle (VM sur le vrai LAN) | faible | **élevé** (coupure hôte possible) | haute (garde-fous + rollback) | **retenu — option experte opt-in** |
| C | **variante D** (taps pré-provisionnés par l'admin, `docs/admin-taps-and-bridge.md`, déjà documentée non câblée) | L2 | admin one-shot | faible | faible | conservée en repli documenté |
| D | **statu quo manuel** (`MARIONNET_BRIDGE` à la main) | L2 | forte | assumé par l'admin | nulle | conservé comme mode « expert manuel » |

**Décision de cadrage (2026-07-18) : « les deux » — A par défaut, B en option experte.**
- **A (NAT privé auto)** tue la barrière pour le cas d'usage majoritaire (« mes VM ont
  besoin d'Internet / des services de l'hôte ») sans jamais risquer la connectivité du
  poste. C'est le modèle éprouvé de libvirt (réseau *default*) : bridge hôte dédié + NAT +
  dnsmasq. Sémantiquement c'est du NAT, pas du L2-sur-le-vrai-LAN — à assumer et à **dire
  dans la GUI**.
- **B (L2 réel auto)** préserve l'usage « vraies IP sur le vrai LAN » et le **lab distribué
  multi-machines**, mais reste opt-in explicite, encadré de garde-fous (détection de la
  carte, avertissement, rollback `at_exit`/erreur), car il peut couper l'hôte.

### 2.2 Points durs identifiés (à traiter aux épisodes d'implémentation)

1. **Périmètre sudoers.** A et B ajoutent des commandes iproute2/iptables au motif scoped de
   `bin/scripts/marionnet-sudoers.sh` (`ip link add … type bridge`, `ip link del`,
   `iptables -t nat …`). Reprendre la discipline de `daemon-elimination` (littéraux, pas de
   `*` libre au-delà du strict nécessaire ; revue sécurité dédiée).
2. **GC des bridges/règles NAT.** Comme les taps `mtap<pid>-*`, nommer `mnbr<pid>-*` et
   purger au lancement les artefacts d'un pid mort (bridge + règle NAT). Garde `owner_pid`
   sur tout `at_exit` (piège `daemon-elimination` ép. 6).
3. **dnsmasq optionnel.** DHCP côté bridge NAT : dépendance + cycle de vie (spawn/kill via la
   classe `process`, `simulation_level.ml`). YAGNI possible : sans dnsmasq, les VM ont une IP
   statique/host-route ; à trancher au POC.
4. **B — détection carte + rollback.** Détecter la carte de route par défaut (`ip route show
   default`), sauvegarder l'état IP, rollback fiable même sur crash. Interaction AppArmor/
   NetworkManager du poste. C'est le vrai coût de B.
5. **Netns (synergie `daemon-elimination` ép. 5).** L'option netns « zéro sudo » différée là-bas
   laissait justement `world_bridge` **hors** de son bénéfice (bridge en ns racine,
   `daemon-elimination.md §12.3` point 1). A/B ici sont orthogonaux au netns ; à recouper si
   ce besoin se concrétise.

## 3. Axe B — travail GUI (comprehensibilité enseignants/étudiants)

Objectif : qu'un étudiant sache *en lisant la GUI* ce que fait `world_bridge`, quand le
préférer à `world_gateway`, et ce qu'il faut (ou plus, après l'axe A) pour qu'il marche.

- **Texte d'aide** (`help_callback`) réécrit : rôle, `world_bridge` **vs** `world_gateway`,
  prérequis (et, à terme, le mode NAT auto sans prérequis). Purge du vocabulaire daté
  (« ethernet socket », `ifconfig/route`) et du `TODO rename` obsolète.
- **Tooltips** (palette, nom, image du dialogue) enrichis pour distinguer les deux composants
  « monde ».
- *(épisodes ultérieurs, après l'axe A)* : sélecteur de **mode** dans le dialogue (NAT auto /
  L2 réel / bridge manuel) ; libellé de palette plus parlant ; éventuel regroupement visuel
  des deux composants « accès au monde ».

## 4. Découpage en épisodes

1. **ép. 0** — *officialisation + étude* (ce document, fiche mémoire, pointeur CLAUDE.md).
   Aucun code fonctionnel. **Fait 2026-07-18.**
2. **ép. 1** — *GUI comprehensibilité (increment 1)* : `help_callback` réécrit + tooltips
   clarifiant `world_bridge` vs `world_gateway`. Sources anglaises seules ; **refresh gettext
   des 12 langues différé** à un épisode i18n consolidé (méthode `daemon-elimination`).
   **Fait 2026-07-18.**
3. **ép. 2+** *(à venir)* — axe A : POC système « NAT bridge privé auto » (option A) sans
   OCaml, puis câblage `Tap_provider`/`world_bridge.ml` + sudoers + GC ; ensuite option B
   (L2 réel, garde-fous) ; refresh i18n consolidé ; compléments GUI (sélecteur de mode).

## 5. Points de vigilance transverses

- **Messages de commit en anglais** (règle dépôt) ; tag/scope = `modernisation-world-bridge`.
- **i18n** : toute modification de `s_`/`f_` déclenche un refresh POT/PO ×12 — regrouper (cf.
  invariant « on ne supporte que des catalogues complets », mémoire `marionnet-i18n`).
- **Sécurité** : ne pas élargir le motif sudoers au-delà du nécessaire ; garde `owner_pid`
  sur les `at_exit` (piège `daemon-elimination` ép. 6).
- **Ne pas régresser** le lab distribué multi-machines (usage 2) ni la surface plus étroite
  obtenue par `daemon-elimination`.

## Journal d'avancement

- **2026-07-18 — épisode 0** : officialisation du chantier `modernisation-world-bridge`
  (fiche mémoire `modernisation-world-bridge`, tag de commits `modernisation-world-bridge`,
  ce document + pointeur `CLAUDE.md`). Étude de l'axe barrière : tableau comparatif (§ 2.1),
  décision de cadrage « A par défaut + B option experte », points durs (§ 2.2). Aucun code
  fonctionnel touché. Prochain pas : épisode 1 (GUI comprehensibilité).
- **2026-07-18 — épisode 1** : GUI comprehensibilité, increment 1. `bin/world_bridge.ml` —
  `help_callback` réécrit (rôle, `world_bridge` vs `world_gateway`, prérequis ; vocabulaire
  daté et `TODO rename` purgés) ; tooltips palette/nom/image enrichis. Sources anglaises
  seules ; refresh gettext ×12 **différé** à un épisode i18n consolidé (catalogues
  temporairement incomplets sur ces chaînes). Vérif : `dune build` rc=0 ; pas de run GUI
  (rig indisponible ; changements = texte d'aide/tooltip). Prochain pas : épisode 2 (POC
  système NAT bridge privé auto, axe A).
