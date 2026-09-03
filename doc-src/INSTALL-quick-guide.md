# Marionnet — quick install

*Copy and paste. Every explanation, every caveat and every troubleshooting entry is in
`INSTALL.md`, whose section numbers are cited here as `INSTALL.md § n`.*

## 0. Which one do I need?

| Your machine | Go to |
|---|---|
| Debian, Ubuntu and derivatives | § 1 |
| Fedora, RHEL family (Rocky, AlmaLinux), openSUSE | § 2 |
| anything else | § 3 |
| you intend to modify Marionnet | § 9 |

Then § 4 (images), § 5 (sudoers rule, **required**) and § 6 (launch), whichever you took.

Archive signing key, used by § 1 and § 2 — compare it with a source that is not this page
(`INSTALL.md § 2`):

```
Marionnet Archive Signing Key <loddo@lipn.univ-paris13.fr>
4A65 3434 0BF9 7733 E74C  9DFC 12E4 6000 225F 0E56
```

## 1. Debian and Ubuntu

### 1.1 Certificates — minimal systems and container images only

```bash
sudo apt update && sudo apt install ca-certificates curl
```

### 1.2 Repository and application

```bash
sudo install -d /etc/apt/keyrings
sudo curl -o /etc/apt/keyrings/marionnet.asc \
     https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc
echo 'deb [signed-by=/etc/apt/keyrings/marionnet.asc] https://www.marionnet.org/download/apt/ ./' \
  | sudo tee /etc/apt/sources.list.d/marionnet.list
sudo apt update
sudo apt install marionnet
```

Never add `-L` to that `curl` (`INSTALL.md § 2`).

### 1.3 Check the key

```bash
sudo apt install gnupg
gpg --show-keys /etc/apt/keyrings/marionnet.asc     # must print the fingerprint above
```

### 1.4 Optional data packages

```bash
sudo apt install marionnet-kernels          # 64-bit UML kernel
sudo apt install marionnet-fs-guignol       # small guest image, machine and router
```

32-bit kernel, for the old kernel/filesystem couples — needs a foreign architecture:

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install marionnet-kernels-i386
```

### 1.5 If a Marionnet tarball was installed here before

```bash
sudo apt install -o Dpkg::Options::=--force-confold marionnet
```

## 2. Fedora, RHEL family and openSUSE

### 2.1 EPEL — RHEL family only

```bash
sudo dnf install epel-release
```

### 2.2 Key, repository, application

```bash
# 1. the key — fetched, LOOKED AT, and only then imported
sudo install -d /etc/pki/rpm-gpg
sudo curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet \
     https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc
gpg --show-keys /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet   # must print the fingerprint of § 2
sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet

# 2. the repository, and the application
sudo curl -o /etc/yum.repos.d/marionnet.repo \
     https://www.marionnet.org/download/rpm/marionnet.repo
sudo dnf install marionnet          # zypper install marionnet, on openSUSE
```

### 2.3 Optional data packages

Same three names as § 1.4. `marionnet-kernels-i386` is not installable on RHEL 10 (no 32-bit
multilib there at all).

## 3. Any distribution — the precompiled tarball

```bash
wget https://www.marionnet.org/download/marionnet-install.sh/marionnet-install.sh
bash marionnet-install.sh --binary --with-deps
```

See what is published, and what is refused and why, before installing anything:

```bash
bash marionnet-install.sh --binary --fetch-only --list
```

## 4. Guest images and UML kernels

```bash
marionnet-get-images
```

**Never pass `--prefix`** here after installing from a package: the images would land where the
application does not look (`INSTALL.md § 5`).

Classroom with no internet access — mirror the release directory once, then:

```bash
marionnet-install.sh --fetch-only --from /srv/marionnet-mirror
```

## 5. Sudoers rule — REQUIRED, and granted by no channel

One account, or several:

```bash
sudo marionnet-sudoers.sh install <user>...
```

A whole classroom, before the students have logins:

```bash
sudo groupadd marionnet                      # if the site has no group of its own
sudo gpasswd -a <login> marionnet            # (or use the LDAP/AD group you already have)
sudo marionnet-sudoers.sh install %marionnet
```

That grants block (a) alone — taps, and the X11 road by which `wireshark` and `xterm` reach your
display. Blocks (b) NAT bridge and (c) LAN bridge are asked for at run time, with the user's own
sudo password. **Read `INSTALL.md § 7.2` before granting (c): it reconfigures the host's own
network card.**

Grant the NAT bridge in advance, without (c) ever entering the picture:

```bash
sudo marionnet-sudoers.sh install --enable-natbridge %marionnet
```

Forbid a block on this machine, for everybody and for good:

```bash
sudo marionnet-sudoers.sh deny --lanbridge     # or --natbridge, or --bridges
```

```bash
marionnet-sudoers.sh policy          # exit 0 if allowed, 3 if denied; says which
```

Take it all back:

```bash
sudo marionnet-sudoers.sh uninstall
```

## 6. Launch, and check the installation

```bash
marionnet                    # or: marionnet -r lab.mar, marionnet --exam, marionnet --help
```

```bash
marionnet -v                 # version and revision
marionnet --paths            # where this installation looks for images, kernels and scripts
```

Marionnet needs an X display, and gives the guests access to it with `xhost`.

## 7. Uninstall

```bash
sudo apt purge marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol
```

```bash
sudo dnf remove marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol
```

Tarball: the `README` inside it lists what to delete. In all cases the sudoers rule stays until
`sudo marionnet-sudoers.sh uninstall`.

## 8. It does not work

| Symptom | Read |
|---|---|
| `server down, no route, wrong URL?` while the site is up | `INSTALL.md § 1` — no certificate store |
| apt ignores the repository, `apt-get update` still exits 0 | `INSTALL.md § 9` |
| `Missing key`, `signature verification failed`, `Failed to import OpenPGP keys` | `INSTALL.md § 2`, `§ 3` — fetch the key again, check the fingerprint |
| the tarball is refused, naming a glibc | `INSTALL.md § 4` — your distribution is older than the build floor |
| Marionnet starts, the guest images do not appear | `INSTALL.md § 5`, then `marionnet --paths` |
| a virtual machine will not start, or nothing opens from a guest | `INSTALL.md § 7` — the sudoers rule |

## 9. From source

```bash
git clone https://git.launchpad.net/marionnet && cd marionnet
make dependencies          # apt packages (build + run time), opam switch, opam packages
dune build                 # a fresh clone needs nothing else: camlp4 preprocessors, C stubs,
                           # version.ml and meta.ml are all built by dune
make install-final-as-root # it calls sudo itself, for the one step which needs it
```
