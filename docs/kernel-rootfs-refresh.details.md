# Détails & constats — chantier `marionnet-kernel-rootfs`

> **Nature de ce fichier.** Trace fine des *constats* et *décisions argumentées* du chantier
> (analyses ponctuelles, tableaux de décision, mesures). Complément de `kernel-rootfs-refresh.md`
> (conception + journal d'épisodes). **Volontairement non résumé dans la mémoire ni le CLAUDE.md** :
> il n'a d'intérêt que si l'on retombe *exactement* sur la même question (p. ex. « ce timer,
> garder ou éliminer ? »). À consulter à la demande, pas à charger en contexte par défaut.

---

## 2026-07-10 — Timers systemd de l'image Trixie : garder ou éliminer ?

**Contexte.** Image `_build.debian-trixie-with-linux-6.12.95.2026-07-10.01h25`. Après le
durcissement « machine nue » de l'épisode 7 (services réseau/serveurs OFF par défaut), il restait
des **timers systemd** activés au boot, non traités par la whitelist de services (qui ne balayait
que `*.target.wants/`, pas `timers.target.wants/`).

**Inventaire réel.** 8 timers activés (`etc/systemd/system/timers.target.wants/`) ;
5 dormants (installés, non activés : `chrony-dnssrv@` [template], `sysstat-{collect,rotate,summary}`,
`systemd-tmpfiles-clean` [cœur systemd]) → aucun traitement requis.

**Fait transversal décisif : les 8 activés ont `Persistent=true`.** Dans une VM éphémère dont
l'horloge démarre « en retard » (ou sans dernier-run enregistré), systemd considère l'échéance
ratée et **rattrape immédiatement au boot**. Conséquence : ces tâches de maintenance « nocturnes »
se déclenchent **en rafale juste après le boot**, quand l'étudiant commence à travailler.

**Grille de décision (Jean).** « Forcer l'étudiant à lancer ça a-t-il une valeur pédagogique
(GARDE), ou est-ce une gêne sans intérêt (ÉLIMINE) ? » — Méthode : **aucun de ces 8 n'est un
service réseau/admin qu'on apprend à administrer** (ceux-là — ssh, bind, dhcp, apache… — sont déjà
OFF-installés, l'étudiant les lance). Ce sont tous de la **maintenance système de fond** → la
question devient « bénéfice réel dans cette VM, ou bruit ? ».

| # | Timer | Rôle réel | Dans une VM UML pédagogique éphémère | Verdict |
|---|-------|-----------|--------------------------------------|---------|
| 1 | **apt-daily** | `apt-get update` + download des paquets | Réseau OFF → échoue ; surtout **verrouille dpkg** au pire moment (l'étudiant fait `apt install` en TP → lock incompréhensible). Anti-reproductibilité. | ÉLIMINE (fort) |
| 2 | **apt-daily-upgrade** | MAJ auto (`apt.systemd.daily install`) | Une image maîtrisée ne doit pas s'auto-mettre à jour (casse la repro). Déjà inerte (pas d'`unattended-upgrades` installé) mais nuisance de principe. | ÉLIMINE (fort) |
| 3 | **dpkg-db-backup** | Backup quotidien de la base dpkg (`/var/backups`) | Sauvegarder la base **dans** une VM jetable n'a aucun sens ; consomme de l'espace sur une image à alléger. | ÉLIMINE |
| 4 | **e2scrub_all** | fsck ext4 *online* via snapshots **LVM** | Image = ext4 simple sur `/dev/ubda`, **pas de LVM** → strictement no-op. Pur bruit. | ÉLIMINE |
| 5 | **fstrim** | TRIM/discard hebdo (SSD) | `/dev/ubd` UML ne propage pas le discard utilement au fichier hôte → no-op en pratique. | ÉLIMINE (faible enjeu) |
| 6 | **lighttpd-maint** | Maintenance de lighttpd | `lighttpd.service` **déjà OFF** (ép. 7) → timer **orphelin** qui tourne dans le vide. Le service web reste installé, l'étudiant l'active (bon comportement) ; le timer doit suivre l'état du service. | ÉLIMINE |
| 7 | **logrotate** | Rotation quotidienne de `/var/log` | Seul avec un argument « hygiène réelle » (VM longue → logs gonflent). Mais VMs Marionnet = courtes, et un `/var/log` qui déborde est un *enseignement*. Inoffensif, à peine utile. | ÉLIMINE (discutable — le plus défendable à garder) |
| 8 | **man-db** | Réindexation quotidienne des pages man | `man` marche sans index frais. `Persistent=true` → se déclenche **à chaque boot** et consomme CPU/IO pendant le travail. | ÉLIMINE |

**Décision (Jean, 2026-07-10) : désactiver les 8.** Aucun n'est un objet d'apprentissage ; tous
sont no-op, anti-reproductibles/nuisibles, orphelins ou inutiles sur cette cible — et tous se
déclenchent au boot (`Persistent=true`). `logrotate` était le seul cas discutable (réalisme
système) ; tranché ÉLIMINE aussi.

**Implémentation retenue.** Passe symétrique au *pass 1* de
`prevent_non_vital_services_from_starting` (branche systemd) : balayer
`etc/systemd/system/timers.target.wants/` et `rm` les symlinks (équivalent offline-safe de
`systemctl disable`). Whitelist vide. → épisode 8.
