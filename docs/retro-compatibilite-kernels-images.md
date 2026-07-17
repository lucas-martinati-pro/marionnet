# Chantier : rétro-compatibilité des vieux couples kernel/image UML

**Slug (commits, mémoire, grep)** : `marionnet-retro-compat-kernels-images`
**Objectif** : faire re-tourner les anciennes images invitées (debian-wheezy-08367,
guignol-18474, mandriva20100215), historiquement couplées à `linux-3.2.64-ghost`, sur un
hôte moderne (noyau ≥ 6.x), en s'appuyant sur un noyau UML récent compilé en **i386**.

## Contexte et diagnostic (étude du 2026-07-17)

### Symptôme

Sur l'hôte de dev/test (Kubuntu 24.04, noyau 6.8.0-134-generic), une VM
`linux-3.2.64-ghost` + wheezy se fige au boot juste après le montage de la racine :

```
wait_stub_done : failed to wait for SIGTRAP, pid = …, n = …, errno = 0, status = 0xb7f
```

précédé d'un dump « Stub registers » avec eip ≈ `0x100080` : le **stub SKAS0 segfaute**
(`0xb7f` = arrêt sur SIGSEGV). Logs de référence versionnés :
`uml/kernel/linux-3.2.64-ghost.with-debian-wheeze.boot-stucked-failure.log` et
`…command-launched-by-marionnet.log`.

### Diagnostic

- Repro CLI minimale hors GUI (COW jetable) : gel encore plus tôt (après « unknown
  partition table »), processus principal en **boucle CPU** (état R, wchan=0).
- **Insensible à `setarch i386 -R -L`** (ASLR désactivé + layout mmap legacy) → pas de
  parade « lanceur » simple. `vm.mmap_min_addr` (65536 < 0x100000) hors de cause.
- `strace -f` inutilisable pour aller plus fin : UML utilise ptrace pour lui-même.
- Pattern historique documenté (HOWTO UML, pratique netkit) : les vieux noyaux **invités**
  cassent quand l'hôte avance ; le remède standard est un invité récent, pas un réglage hôte.
- **Recompiler le 3.2.64 est une impasse** : le problème est dans le code du stub lui-même
  (pas dans sa compilation), et gcc moderne ne compile plus un arbre 3.2.

### Contrainte d'architecture

`linux-3.2.64-ghost` est un ELF **i386** et les vieilles images sont des userlands
**i386**. Le `linux-6.12.95` installé (chantier `marionnet-kernel-rootfs`) est **x86_64**
et UML n'a pas d'émulation 32 bits invitée → il faut une **variante i386** du noyau moderne.

### Solution démontrée (preuve du 2026-07-17)

Un `linux-6.12.95` compilé `ARCH=um SUBARCH=i386` (defconfig + `EXT2/EXT3/EXT4_FS`,
`HOSTFS`, `BLK_DEV_UBD`, `UML_NET{,_TUNTAP,_DAEMON}` ; gcc 13 multilib) **boote les deux
images installées jusqu'à `login:`** sur l'hôte 6.8 :

- wheezy-08367 : `VFS: Mounted root (ext4)` → `INIT: version 2.88` → runlevel 2 → `factotum login:` ;
- guignol-18474 (buildroot) : boot complet → `buildroot login:`.

## Plan d'épisodes (prévisionnel)

1. **Build reproductible + install** : variante i386 dans `uml/pupisto.kernel/`
   (config gelée `CONFIG-…-i386` sur le modèle de `CONFIG-modern-base`), epithet distinct
   **`linux-6.12.95-i386`** dans `kernels/` (deux archis de la même version doivent coexister).
2. **Couplage Marionnet** : étendre `SUPPORTED_KERNELS` des `.conf` wheezy/guignol
   (aujourd'hui `/3.2.[6-9]/`) avec le nouvel epithet + paramètres console adéquats ;
   vérifier l'applicabilité des `BOOT_QUIRKS` OCaml (table par noyau ≥ 5) ; test GUI.
3. **Ghostification** : pas de patch ghost sur 6.12 → le vieux relay embarqué appellera
   `ethghost` en vain. Piste privilégiée : hook **`.relay`** via hostfs (supporté par les
   images post-juillet-2013, donc wheezy 2014 ; à vérifier pour guignol 2017) pour une
   ghostification **netns** façon trixie **sans modifier les images**
   (cf. `machine-template.relay` installé et l'archi netns de `marionnet-kernel-rootfs`).
4. **Mandriva** : cas distinct — l'image `machine-mandriva20100215` n'est pas installée
   (seul le `.conf`, qui exige un `[2.6.18-ghost]` absent lui aussi) : restaurer l'image,
   puis décider (même voie i386 moderne, ou abandon documenté).

**Hors périmètre** : ressusciter la série 3.2 (recompilation/backport du stub) ; le
lancement des couples *modernes* (trixie), couvert par `marionnet-kernel-rootfs`.

## Journal d'avancement

- **2026-07-17 — épisode 0 (étude)** : diagnostic de cause (stub SKAS0 des vieux UML
  incompatible hôte 6.8, aucune parade lanceur), preuve de la solution : UML 6.12.95
  `SUBARCH=i386` boote wheezy et guignol jusqu'à `login:` (build ~2 min, boots ~1 min,
  COW jetables). Officialisation du chantier (doc + fiche mémoire + pointeur CLAUDE.md).
