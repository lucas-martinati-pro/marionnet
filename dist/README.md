# Paquets d'installation Marionnet v1.0.456 pour Ubuntu

Ce dossier contient les paquets Debian (`.deb`) précompilés pour installer facilement **Marionnet 1.0.456** sur Ubuntu (22.04, 24.04, etc.) avec tous les correctifs pour les noyaux Linux récents (élimination de l'erreur `/sbin/getty: Input/output error`).

---

## Option 1 : Installation Tout-en-un (Recommandée)

Le paquet `marionnet-all-in-one_1.0.456_amd64.deb` embarque **l'application Marionnet 1.0.456**, les **noyaux UML 64-bit et 32-bit (6.12.95)**, ainsi que **le système de fichiers Guignol (machine et routeur)**.

Exécutez simplement :
```bash
./install.sh
```

Ou manuellement :
```bash
sudo apt update
sudo apt install -y ./marionnet-all-in-one_1.0.456_amd64.deb
```

`apt` résoudra et installera automatiquement toutes les dépendances Ubuntu nécessaires (`vde2`, `graphviz`, `uml-utilities`, `xterm`, `socat`, etc.).

---

## Option 2 : Installation Modulaire

Si vous préférez séparer l'application de ses noyaux et images :

```bash
sudo apt update
sudo apt install -y ./marionnet_1.0.456_amd64.deb ./marionnet-kernels_6.12.95_amd64.deb ./marionnet-kernels-i386_6.12.95_amd64.deb ./marionnet-fs-guignol_18474_all.deb
```

---

## Vérification

Pour vérifier que la version 1.0.456 est bien active :
```bash
marionnet -v
# Doit afficher : marionnet version 1.0.456
```
