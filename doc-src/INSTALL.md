# Installing Marionnet

*Which channel to take, what each one lays down, and what a machine still owes you afterwards.*

Marionnet is published through **three channels**, all fed by the same release directory on
`www.marionnet.org` and all carrying the **same binary**. The one to take depends on what your
machine's package manager is, not on what you intend to do with Marionnet:

| Your machine | Take | § |
|---|---|---|
| Debian, Ubuntu and derivatives | the **apt repository** | § 2 |
| Fedora, RHEL family (Rocky, AlmaLinux), openSUSE | the **dnf/zypper repository** | § 3 |
| anything else — or you want no package manager involved | the **precompiled tarball** | § 4 |
| you intend to modify Marionnet | **from source** | § 6 |

Whatever the channel, the **guest images and the UML kernels are fetched separately** (§ 5): they
weigh gibibytes, they change on their own schedule, and a package manager is not what they are
for. Marionnet starts without them and says so.

Every relative path on this page is relative to **the directory this file is in**: `doc-src/` in
the sources, `<prefix>/share/doc/marionnet/` on a machine where Marionnet is installed.

## 1. Before anything, on a minimal Debian or Ubuntu

The three channels reach the site over **https**, and a *minimal* Debian or Ubuntu system —
notably a bare container image — carries **no certificate store at all** (measured on Debian 12
and 13 and on Ubuntu 24.04 and 26.04; the RPM-family images do carry one). Without it `apt` will
not read our repository and the installer will not read the catalogue, both while the server is
perfectly up:

```bash
sudo apt update && sudo apt install ca-certificates curl
```

`curl` is in that line for the same reason: a *slim* image has no downloader either, and § 2
fetches the archive key with one (`wget` does just as well — `wget -O` in place of `curl -o`).

`marionnet-install.sh` diagnoses the certificate case by name rather than blaming the network,
but it cannot repair it: installing that package needs a working package manager, which is the
thing at stake.

## 2. Debian and Ubuntu — the apt repository

Measured on **Debian 12, Debian 13, Ubuntu 24.04 and Ubuntu 26.04**.

```bash
sudo install -d /etc/apt/keyrings
sudo curl -o /etc/apt/keyrings/marionnet.asc \
     https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc
echo 'deb [signed-by=/etc/apt/keyrings/marionnet.asc] https://www.marionnet.org/download/apt/ ./' \
  | sudo tee /etc/apt/sources.list.d/marionnet.list
sudo apt update
sudo apt install marionnet
```

`download/apt` is a **stable entry point**: it follows the current publication series, so the
line above does not have to be edited when the series changes.

### The key, and what signing does and does not buy

The repository's `Release` file is signed, and `signed-by=` is what makes apt verify it. The
key is:

```
Marionnet Archive Signing Key <loddo@lipn.univ-paris13.fr>
4A65 3434 0BF9 7733 E74C  9DFC 12E4 6000 225F 0E56
```

**Notice where the key comes from: `git.launchpad.net`, not `www.marionnet.org`.** That is the
whole point, and it is worth two minutes of your attention.

Without a signature, everything you download is protected only by https, which proves that the
server was not impersonated — and nothing about who wrote the packages. Whoever controls that
server rewrites the packages *and* the digests that vouch for them: everything stays consistent,
everything verifies, and everything is false. The signature moves the point of trust to a private
key which does not live on the server.

*What it protects, concretely*: the machines **already installed**. Such a machine never re-reads
this page; at every `apt upgrade` it checks against the key already on its disk. Somebody who
takes the server tomorrow cannot push anything to them — apt refuses, and says so. Without a
signature, an entire classroom would take a trojanised upgrade in silence, on machines where
Marionnet installs a sudoers rule.

*What it does not protect*: your very first installation, if you learn everything from a
compromised site — the page would then name another key, and it would all verify. No signature
solves that (Debian's own keyring arrives in an ISO downloaded from a website). What breaks the
circle is comparing the fingerprint above with **a source which is not this page**: the git
repository, a printed course handout, a machine where Marionnet is already installed. In a
classroom, the fingerprint read out once at the start of the term settles it for everyone.

**Check what you fetched — this step is not optional here**, and not only for the reason above.
Measured: `git.launchpad.net` answers `200` most of the time and, about one request in six, a
`302` towards its OpenID login page. `curl` will happily write whatever came back into the file,
so a key fetch can quietly leave you with something that is not a key. (Do **not** add `-L`: that
follows the redirect and writes the *login page*, which is worse — a failure that looks like a
success.)

```bash
sudo apt install gnupg
gpg --show-keys /etc/apt/keyrings/marionnet.asc     # must print the fingerprint above
```

If it prints anything else — or nothing — fetch it again. apt itself does not need `gnupg` to
verify the repository (it has its own verifier); you need it only to *read* what you fetched.

`wget -O /etc/apt/keyrings/marionnet.asc <url>` does just as well, and has the same caveat.

`apt install marionnet` installs **the application alone** — the data packages are `Suggests:`,
so that this command means the same thing here as `dnf install marionnet` does in § 3. The other
three packages, all optional:

| Package | What it carries |
|---|---|
| `marionnet-kernels` | the 64-bit UML kernel |
| `marionnet-fs-guignol` | the small guest image, machine *and* router |
| `marionnet-kernels-i386` | the 32-bit UML kernel, for the old kernel/filesystem couples |

`marionnet-kernels-i386` needs a **foreign architecture enabled on your machine**, because the
32-bit kernel's interpreter is `/lib/ld-linux.so.2` and only `libc6:i386` owns that path:

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install marionnet-kernels-i386
```

Without it, apt refuses the package by naming `libc6:i386`. That is why the 32-bit kernel is a
package of its own: enabling a foreign architecture is a decision, and it should not be imposed
on everyone who wants the 64-bit one.

**If a Marionnet tarball (§ 4) was installed on this machine first**, `/etc/marionnet/marionnet.conf`
already exists and dpkg will ask what to do with it — and a *non-interactive* `apt install` fails
there, because `DEBIAN_FRONTEND=noninteractive` governs *debconf*, not dpkg's conffile prompt. To
keep the configuration you already have:

```bash
sudo apt install -o Dpkg::Options::=--force-confold marionnet
```

The package's version of the file is then left beside it as `marionnet.conf.dpkg-dist`. Note that
the two files disagree on one thing which matters: a package installs under `/usr`, a tarball
under `/usr/local`.

## 3. Fedora, RHEL family and openSUSE — the dnf/zypper repository

Measured on **Fedora 42, Rocky Linux 10, AlmaLinux 10 and openSUSE Leap 16**.

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

`download/rpm` is the stable entry point, as `download/apt` is for § 2.

### The key, on this side

It is **the same key as § 2** — same fingerprint, same place to fetch it from, and everything
§ 2 says about what a signature does and does not buy applies here word for word. The middle line
of the block above is the one not to skip, and it comes **before** `rpm --import` on purpose:
importing is the act of trusting, so looking at what you fetched afterwards would be looking too
late. The caveat is the same as in § 2 — `git.launchpad.net` answers a redirect about one request
in six, and `curl` writes whatever came back.

If `gpg` is not on the machine: `sudo dnf install gnupg2` (`zypper install gpg2` on openSUSE).
Neither `dnf` nor `rpm` needs it — they have their own verifier; you need it only to *read* the
key, exactly as in § 2.

What differs is the *shape* of the verification, not its strength. Where apt has one signature on
`Release` which covers every package by digest, rpm has **two** mechanisms, and the stanza asks
for both:

| Setting | What it verifies |
|---|---|
| `gpgcheck=1` | **each package**, from a signature `rpmsign` put inside the file itself |
| `repo_gpgcheck=1` | **the index**, from `repodata/repomd.xml.asc` beside it |

Note also that the stanza names the key as a **local file** (`gpgkey=file:///etc/pki/rpm-gpg/…`)
and not as a URL, which is why you fetch it yourself in the block above. That is deliberate and
measured: `dnf` fetches `gpgkey=` itself and *follows redirects*, so a `gpgkey=` naming
`git.launchpad.net` downloads the login page one time in six and the installation dies with
`Failed to import OpenPGP keys` — after downloading every package. Unlike `curl`, `dnf` cannot be
told not to follow. Fetching the key by hand also restores the step that matters: a key the
package manager fetches on its own is a key nobody ever looked at.

`dnf` may still show you a fingerprint and ask whether to accept the key: it keeps a keyring of
its own for `repo_gpgcheck`, which `rpm --import` above does not feed. Compare what it shows with
the fingerprint of § 2 before answering yes.

**On the RHEL family, enable EPEL first**: `gtksourceview3`, one of Marionnet's run-time
dependencies, lives there and not in the base repositories.

```bash
sudo dnf install epel-release
```

The repository also carries **`vde2` and `uml-utilities`**, which Marionnet cannot run without
and which *no* RPM distribution packages — measured on Rocky 9 with EPEL, CRB and epel-next, and
on Fedora 42 and 44. They are built here from the Debian source packages, patch series included.
`dnf` resolves them from the same directory, so you do not have to know they exist; on openSUSE,
which *does* ship `vde2`, the distribution's own package is used instead and ours is not pulled.

The optional data packages are the same three as in § 2, under the same names. The 32-bit kernel
package has no `dpkg --add-architecture` counterpart here — multilib is native — but RHEL 10 has
**removed 32-bit multilib entirely**, so on that family `marionnet-kernels-i386` is simply not
installable; that is why it is a separate package, so that its refusal does not carry away the
64-bit one.

## 4. Any distribution — the precompiled tarball

The application is also published as a relocatable tarball, named
`marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz`. The two last fields are what make the
choice: the artefact runs on a machine whose architecture is `<arch>` and whose glibc is **at
least** `<x.y>` — a dynamically linked binary demands a glibc no older than the one it was linked
against, and glibc's symbol versioning guarantees the other direction only.

The published artefact is built on the **oldest system we serve** (currently Debian 12,
glibc 2.36), so it runs on every distribution listed in § 2 and § 3.

This channel is **not signed**. Each artefact's digest is in `SHA256SUMS`, which the installer
checks while it downloads — that proves the file arrived whole, not who wrote it, since the
catalogue travels the same road as the tarballs. The two package channels (§ 2 and § 3) are
signed; this one is not. If that distinction matters to you, take one of them. It does *not* run on
Rocky 9 or openSUSE Leap 15.6, whose glibc is older; both refuse it by naming the glibc.

The simplest way is to let the installer choose and unpack it for you:

```bash
wget https://www.marionnet.org/download/marionnet-install.sh/marionnet-install.sh
bash marionnet-install.sh --binary --with-deps
```

`--binary` needs root (it uses `sudo` if you are not root). To see what is published before
installing anything, ask for the catalogue — **including what it refuses and why**:

```bash
bash marionnet-install.sh --binary --fetch-only --list
```

`--list` is given *with a mode*: it is the mode which says whether the application, the data, or
both are of interest, and the script declines to guess (under its other name,
`marionnet-get-images`, the mode is implied — § 5). By hand, if you prefer:

```bash
xz -dc -T0 marionnet_<...>.tar.xz | tar xf -
cd marionnet_<...>/ && sudo ./install.sh --prefix /usr/local
```

`install.sh` is the *same* script in both cases — the installer merely runs the one travelling
inside the tarball. It copies `bin/` and `share/` under the prefix, writes
`/etc/marionnet/marionnet.conf` (which is what lets the tarball live anywhere) and installs the
sudoers rule (§ 7). By default it **names** the missing apt packages without installing anything;
`--with-deps` installs them, `--no-deps` does not even look. Its `--help` lists the rest.

The packages Marionnet needs at run time travel with the tarball as data, one name per line, in
`REQUIRED-PACKAGES-RUNTIME`. On a Debian-like system, by hand:

```bash
sudo apt install $(tr '\n' ' ' < REQUIRED-PACKAGES-RUNTIME)
```

## 5. The guest images and the UML kernels

Whichever channel installed the application, this is the command that offers the published images
and kernels as a list to tick, and fetches what you ticked:

```bash
marionnet-get-images
```

It shows as *already installed* — ticked, and not editable — every image whose modification time
matches the `MTIME` its `.conf` records, which is the field user-mode-linux itself checks against
a backing file.

**Do not pass `--prefix` after installing from a package.** Given no `--prefix`, the images go
where *the Marionnet installed here* looks for them — asked of `marionnet.native --paths`, the
only reader of the configuration cascade — which is `/usr/share/marionnet/...` for a package and
`/usr/local/share/marionnet/...` for a tarball. A `--prefix` written by hand is how images end up
in a directory the application never reads: nothing fails, and the images simply do not appear.

Two of the images (Debian wheezy, Debian trixie) are deliberately outside apt and dnf: they weigh
gibibytes. The small `guignol` image and the kernels are also available as packages (§ 2, § 3) if
you would rather your package manager owned them.

**For a classroom with no internet access**, mirror the release directory once and point every
machine at the copy — a local directory and a URL are the same argument:

```bash
marionnet-install.sh --fetch-only --from /srv/marionnet-mirror
```

## 6. From source

For anyone who intends to modify Marionnet. The toolchain is **OCaml 5.4.1 through opam**, plus
camlp4; the guest images and kernels still come from § 5.

```bash
git clone https://git.launchpad.net/marionnet && cd marionnet
make dependencies          # apt packages (build + run time), opam switch, opam packages
dune build                 # a fresh clone needs nothing else: camlp4 preprocessors, C stubs,
                           # version.ml and meta.ml are all built by dune
make install-final-as-root # it calls sudo itself, for the one step which needs it
```

`make dependencies` installs the apt build dependencies, creates the opam switch and installs the
opam packages; run its parts separately (`make apt-dependencies`, `make opam-switch`,
`make opam-dependencies`) if you want to see them one at a time.

Two things worth knowing before you build:

* `dune build` is **not** a typecheck of the whole project — for an executable, dune compiles only
  what `marionnet.ml` reaches. `make check` compiles every module.
* to run Marionnet from the opam switch instead of installing it system-wide, use
  `make install-for-testing` (and `make rebuild-for-final` / `make rebuild-for-testing` when you
  switch between the two: the prefix is compiled in as a default).

## 7. What is still owed after any channel: the sudoers rule

Marionnet builds its network taps with `iproute2`, which needs one **scoped** sudoers rule. No
channel grants it automatically, and the packages deliberately do not: a package installation
cannot tell which human a machine belongs to. Run, as an administrator:

```bash
sudo marionnet-sudoers.sh install <user>
```

That grants the socle — block (a) — without which nothing works. The NAT bridge and LAN bridge
grants are separate blocks, asked for by the user, from the interface, the day a bridge component
is started. The tarball's `install.sh` installs block (a) for you (unless `--no-sudoers`).

To take it away: `sudo marionnet-sudoers.sh uninstall`.

## 8. Removing Marionnet

* **apt**: `sudo apt purge marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol`
* **dnf**: `sudo dnf remove marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol`
  (`sudo zypper remove ...`, on openSUSE)
* **tarball**: the `README` inside it lists what to delete, prefix by prefix.

In all three cases the sudoers rule was never granted by the installation, so it is not taken away
by the removal: `sudo marionnet-sudoers.sh uninstall`.

## 9. When something does not work

| Symptom | What it is |
|---|---|
| `server down, no route, wrong URL?` while the site is up | no certificate store — § 1 |
| apt says the repository is ignored, `apt-get update` still exits 0 | same cause, or the `sources.list` line was edited; apt reports this as a *warning* |
| `Missing key <fingerprint>`, or `signature verification failed` | the file in `/etc/apt/keyrings/` is not the archive key — fetch it again (§ 2) and compare the fingerprint |
| apt keeps offering the package although it just refused the repository | it is reusing the index it already had: `sudo rm -rf /var/lib/apt/lists/*` then `apt update` |
| `Failed to import OpenPGP keys`, or dnf reports the repository has no packages | the key file of § 3 is missing, was not accepted, or is not a key at all — fetch it again and check the fingerprint before importing |
| the tarball is refused, naming a glibc | your distribution is older than the build floor — § 4 |
| `marionnet-kernels-i386` is refused, naming `libc6:i386` | `dpkg --add-architecture i386` — § 2 |
| Marionnet starts but the guest images do not appear | they were laid down under a prefix the application does not read — § 5 |
| *Unsatisfied dependency* at startup | `vde2`, `graphviz` or `uml-utilities` is missing; the tarball channel names what is missing, `--with-deps` installs it |
| a virtual machine will not start, taps cannot be built | the sudoers rule — § 7 |

## Where to go next

| Page | Read it for |
|---|---|
| `INSTALL.FR.md` | this same page in French |
| `teacher-guide.md` | preparing a lab, running the session, marking it |
| `scripting/README.md` | driving Marionnet from a script, through the control channel |
| `exam-mode.md` | what an exam session records |
| `project-format-v3.md` | the `.mar` project format |
