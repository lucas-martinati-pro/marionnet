# Installing Marionnet

*Which method to use, what each one installs on the filesystem, and what you must — or may — do
afterwards.*

Marionnet is published in **three ready-made forms**, all fed by the same release directory on
`www.marionnet.org` and all carrying the **same binary**. Which one to take depends on your
machine's package manager, not on what you intend to do with Marionnet:

| Your machine | Take | § |
|---|---|---|
| Debian, Ubuntu and derivatives | the **apt repository** | § 2 |
| Fedora, RHEL family (Rocky, AlmaLinux), openSUSE | the **dnf/zypper repository** | § 3 |
| anything else — or you want no package manager involved | the **precompiled tarball** | § 4 |
| you intend to modify Marionnet | **from source** | § 6 |

Whatever the method, the **guest images and the UML kernels are fetched separately** (§ 5): they
weigh gibibytes and change on their own schedule. Marionnet starts without them and says so.

Marionnet is a graphical program: it needs an X display (`DISPLAY`), and it opens that display to
the guests with `xhost` (§ 7.2).

Every relative path on this page is relative to **the directory this file is in**: `doc-src/` in
the sources, `<prefix>/share/doc/marionnet/` on a machine where Marionnet is installed.

## 1. Before anything, on a minimal Debian or Ubuntu

All three methods reach the site over **https**, and a *minimal* Debian or Ubuntu system —
notably a bare container image — carries **no certificate store at all** (measured on Debian 12
and 13 and on Ubuntu 24.04 and 26.04; the RPM-family images do carry one). Without it, `apt` will
not read our repository and the installer will not read the catalogue, both while the server is
perfectly up:

```bash
sudo apt update && sudo apt install ca-certificates curl
```

`curl` is in that line for the same reason: a *slim* image has no downloader either, and § 2
fetches the archive key with one (`wget -O` in place of `curl -o` does just as well).

`marionnet-install.sh` names this cause instead of blaming the network, but it cannot repair it:
installing that package needs the working package manager which is exactly what is at stake.

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

### The key

The repository's `Release` file is signed, and `signed-by=` is what makes apt verify it. The key
is:

```
Marionnet Archive Signing Key <loddo@lipn.univ-paris13.fr>
4A65 3434 0BF9 7733 E74C  9DFC 12E4 6000 225F 0E56
```

It comes from `git.launchpad.net`, **not** from `www.marionnet.org`, and that is the point.
https only proves that the server was not impersonated; whoever controls that server rewrites the
packages *and* the digests that vouch for them. A signature moves the point of trust to a private
key which does not live there.

*What it protects*: the machines **already installed**. They never re-read this page — at every
`apt upgrade` they check against the key on their own disk, so nobody who takes the server
tomorrow can push them a trojanised upgrade, on machines where Marionnet installs a sudoers rule.
*What it does not protect*: your very first installation, if you learn everything from a
compromised page, which would name another key and verify perfectly. The way out is to compare
the fingerprint above with **a source which is not this page**: the git repository (§ *Where to
go next*), a printed handout, a machine where Marionnet already runs. In a classroom, reading it
out once at the start of term settles it for everyone.

**Check what you fetched — this step is not optional.** Measured: `git.launchpad.net` answers
`200` most of the time and, about one request in six, a `302` towards its OpenID login page, and
`curl` writes whatever came back. Do **not** add `-L`: it follows the redirect and writes the
*login page* — a failure that looks like a success.

```bash
sudo apt install gnupg
gpg --show-keys /etc/apt/keyrings/marionnet.asc     # must print the fingerprint above
```

If it prints anything else — or nothing — fetch it again. apt does not need `gnupg` to verify the
repository (it has its own verifier); you need it to *read* what you fetched.

### The packages

`apt install marionnet` installs **the application alone** — the data packages are `Suggests:`,
so that this command means the same thing here as `dnf install marionnet` does in § 3. They are
not accessories: **alone, the application boots nothing.** A guest needs a filesystem *and* a
kernel that filesystem declares support for, and Marionnet **does not offer** a filesystem for
which no supported kernel is installed. Nothing fails and nothing is said: the component is
simply absent from the list.

| Package | What it carries — and what is missing without it |
|---|---|
| `marionnet-kernels` | the 64-bit UML kernel `linux-6.12.95`. Without it, **the recent images** (Debian trixie) are not offered |
| `marionnet-fs-guignol` | the small guest image, machine *and* **router** — the only router filesystem published. Without it, **no router can be built at all** |
| `marionnet-kernels-i386` | the 32-bit UML kernel `linux-6.12.95-i386`. Without it, **guignol and wheezy** are not offered, and with them every `.mar` project made before 2026 |

**A router costs two packages, not one.** Measured in the published `.conf`: guignol declares
`SUPPORTED_KERNELS='/3.2.[6-9]/ /-i386$/'`, which `linux-6.12.95` does not match. So
`marionnet-fs-guignol` needs `marionnet-kernels-i386` — the 64-bit kernel will not run it — and
the foreign architecture below is not a matter of old projects only: it is what a router costs
today.

`marionnet-kernels-i386` needs a **foreign architecture enabled on your machine**, because the
32-bit kernel's interpreter is `/lib/ld-linux.so.2` and only `libc6:i386` owns that path:

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install marionnet-kernels-i386
```

Without it, apt refuses the package by naming `libc6:i386`. Enabling a foreign architecture is a
decision, which is why the 32-bit kernel is a package of its own.

**If a Marionnet tarball (§ 4) was installed on this machine first**, `/etc/marionnet/marionnet.conf`
already exists and dpkg will ask what to do with it — and a *non-interactive* `apt install` fails
there, because `DEBIAN_FRONTEND=noninteractive` governs *debconf*, not dpkg's conffile prompt. To
keep the configuration you already have:

```bash
sudo apt install -o Dpkg::Options::=--force-confold marionnet
```

The package's version of the file is then left beside it as `marionnet.conf.dpkg-dist`. The two
disagree on one thing which matters: a package installs under `/usr`, a tarball under
`/usr/local`.

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

Same key, same place, same caveats as § 2 — including the redirect one request in six. The middle
line of the block above comes **before** `rpm --import` on purpose: importing *is* the act of
trusting, so looking afterwards would be looking too late. If `gpg` is missing:
`sudo dnf install gnupg2` (`zypper install gpg2` on openSUSE); neither `dnf` nor `rpm` needs it.

What differs is the *shape* of the verification, not its strength. Where apt has one signature on
`Release` covering every package by digest, rpm has **two** mechanisms, and the stanza asks for
both:

| Setting | What it verifies |
|---|---|
| `gpgcheck=1` | **each package**, from a signature `rpmsign` put inside the file itself |
| `repo_gpgcheck=1` | **the index**, from `repodata/repomd.xml.asc` beside it |

The stanza names the key as a **local file** (`gpgkey=file:///etc/pki/rpm-gpg/…`) and not as a
URL, which is why you fetch it yourself above: `dnf` fetches `gpgkey=` itself and *follows
redirects* — it cannot be told not to — so a URL pointing at `git.launchpad.net` downloads the
login page one time in six and kills the installation with `Failed to import OpenPGP keys`, after
downloading every package.

`dnf` may still show you a fingerprint and ask whether to accept the key: it keeps a keyring of
its own for `repo_gpgcheck`, which `rpm --import` does not feed. Compare what it shows with the
fingerprint of § 2 before answering yes.

**On the RHEL family, enable EPEL first**: `gtksourceview3`, one of Marionnet's run-time
dependencies, lives there and not in the base repositories.

```bash
sudo dnf install epel-release
```

The repository also carries **`vde2` and `uml-utilities`**, which Marionnet cannot run without
and which *no* RPM distribution packages (measured on Rocky 9 with EPEL, CRB and epel-next, and
on Fedora 42 and 44); they are built here from the Debian source packages. `dnf` resolves them
from the same directory, so you do not have to know they exist — except on openSUSE, which ships
`vde2` and whose own package is used instead.

The three data packages are the same as in § 2, under the same names, and needed for the same
things. Multilib is native here, so the 32-bit kernel needs no `dpkg --add-architecture`
counterpart; but RHEL 10 has **removed 32-bit multilib entirely**, so on that family
`marionnet-kernels-i386` is simply not installable — which is why it is a separate package, so
that its refusal does not carry away the 64-bit one. Take the consequence with it: no 32-bit
kernel means no guignol and no wheezy, hence **no router** on RHEL 10 (§ 2) — a temporary
state of affairs, a 64-bit router image being planned for publication.

## 4. Any distribution — the precompiled tarball

The application is also published as a relocatable tarball, named
`marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz`. The two last fields are what make the
choice: the artefact runs on a machine whose architecture is `<arch>` and whose glibc is **at
least** `<x.y>`, glibc's symbol versioning guaranteeing compatibility in that direction only. The
published artefact is built on the **oldest system we serve** (currently Debian 12, glibc 2.36),
so it runs on every distribution listed in § 2 and § 3, and on none older — Rocky 9 and openSUSE
Leap 15.6 refuse it by naming the glibc.

This form is **not signed**: `SHA256SUMS`, which the installer checks while downloading, proves
that the file arrived whole, not who wrote it — the catalogue travels the same road as the
tarballs. If that distinction matters to you, take § 2 or § 3.

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

Whichever method installed the application, this is the command that offers the published images
and kernels as a list to tick, and fetches what you ticked:

```bash
marionnet-get-images
```

It shows as *already installed* — ticked, and not editable — every image whose modification time
matches the `MTIME` its `.conf` records, which is the field user-mode-linux itself checks against
a backing file.

**Do not pass `--prefix` after installing from a package.** Given no `--prefix`, the images go
where *the Marionnet installed here* looks for them — asked of `marionnet --paths`, the only
reader of the configuration cascade — which is `/usr/share/marionnet/...` for a package and
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

Run the parts of `make dependencies` separately (`make apt-dependencies`, `make opam-switch`,
`make opam-dependencies`) if you want to see them one at a time. Two things worth knowing:

* `dune build` is **not** a typecheck of the whole project — for an executable, dune compiles only
  what `marionnet.ml` reaches. `make check` compiles every module.
* to run Marionnet from the opam switch instead of installing it system-wide, use
  `make install-for-testing` (and `make rebuild-for-final` / `make rebuild-for-testing` when you
  switch between the two: the prefix is compiled in as a default).

## 7. What is still owed after any method: the sudoers rule

Marionnet builds its network taps with `iproute2`, which needs one **scoped** sudoers rule. No
installation method grants it automatically, and the packages deliberately do not: a package
installation cannot tell which human a machine belongs to. Run, as an administrator:

```bash
sudo marionnet-sudoers.sh install <user>...
```

That grants the **socle** — block (a) — without which nothing works. The tarball's `install.sh`
installs it for you (unless `--no-sudoers`). To take everything back:
`sudo marionnet-sudoers.sh uninstall`.

### 7.1 Granting: one account, several, or a whole classroom

The command is **additive**: granting a second person never takes the first one's grant away, and
`sudo marionnet-sudoers.sh uninstall <user>` takes one grant back while leaving the others in
place. An account that does not exist is refused — sudoers would happily name it, and grant it the
day somebody creates that login.

A principal is an account, or a **group** in sudoers spelling. A classroom is why: whoever sets a
room up does not know the logins of the students who will sit in it.

```bash
sudo groupadd marionnet                      # if the site has no group of its own
sudo gpasswd -a <login> marionnet            # (or use the LDAP/AD group you already have)
sudo marionnet-sudoers.sh install %marionnet
```

Every member of the group is then granted, including the ones enrolled next week. Two things to
know about a group grant. `ALL` is **refused**: what a file grants must have been decided by
somebody, and it would include system accounts. And the tap-creation line, which for a named
account binds the tap to that login, has to accept any owner for a group — sudoers cannot spell
"the caller" in a command argument; a member may therefore create a tap **owned by somebody
else**, though nobody gains a tap they can open and the confinement to `mtap*` is untouched.

`sudo -l -U <login>` is the question about effective rights; `marionnet-sudoers.sh check` answers
about the principals a file *names*, so a member of a granted group is not one.

### 7.2 The three blocks, and what each one does to this machine

Read this before granting anything beyond the socle. The three blocks are three files in
`/etc/sudoers.d/`, granted at three different moments, and they are **not** equally dangerous.

| Block | Granted | What it lets the account do to the host |
|---|---|---|
| **(a) ghost taps** | at install time, by the administrator | Create and destroy `mtap*` interfaces, give them the fixed address `172.23.0.254/32` and route `172.23.*` to them. Confined to `mtap*`: nothing else on the machine can be reached through it. This tap is also the road by which the X11 clients of a guest reach the host's display — `xterm` on a machine or a router, and above all **`wireshark`** started inside a router or a machine to capture its own traffic; Marionnet opens the door with `xhost +172.23.0.254`. Without this block Marionnet runs degraded: no graphics from the guests, no router terminals. |
| **(b) NAT bridge** | at run time, from the interface | Build the private bridge `mnbr*` and NAT the guests behind it. |
| **(c) LAN bridge** | at run time, from the interface | Put the host's **own network card** into a bridge, so guests sit on the real local network. |

**(b), in detail.** It creates a bridge `mnbr*` with the `.1/24` address of a private network; it
turns `net.ipv4.ip_forward` **on**, which is host-wide and not per-interface (Marionnet restores
it on teardown only if it is the one that turned it on); it adds one `MASQUERADE` rule and two
`FORWARD` rules with `iptables`, **every one of them carrying the comment
`marionnet-natbridge:mnbr*`** — the sudoers rule requires that tag, so no rule your firewall
already has can be added, changed or deleted through this grant. Optionally it starts a
**`dnsmasq` bound to that bridge alone** (DHCP in `.100-.200`, plus DNS for the guests), which is
why `dnsmasq-base` is a runtime dependency. Optionally again, IPv6: a ULA `/64`, Router
Advertisements sent by that same dnsmasq, and NAT66 on `ip6tables` — and since IPv6 forwarding is
**not** per-interface, turning it on makes the whole host a router, and a router ignores the
advertisements it receives; a tiny zero-argument gate (`marionnet-ipv6.sh`) therefore remembers
and restores `accept_ra`. The host card, its addresses and its routes are **never named** in this
block, so they cannot be touched through it.

**(c), in detail — it is the host's networking, and it cannot be scoped.** A LAN bridge *is* the
host's card enslaved to `mnlan0`, with the host's IPv4 address and default route **moved onto the
bridge** and the card's MAC cloned onto it. There is exactly one per host (a card has one master),
so two Marionnet sessions share it. What to weigh before granting it:

* a window of a few milliseconds during which the host has **no route out** (the address is put on
  the bridge before being removed from the card, so it is never nowhere);
* the virtual machines appear **on the real LAN, with their own MAC addresses** — a switch with
  port security, or a campus network policy, may well refuse that;
* your network manager (NetworkManager, netplan, systemd-networkd) may undo or fight the change;
* the last three lines of the sudoers file it installs are **not restricted to any device** —
  `ip addr add|del * dev *` and `ip route add default via * dev *` — because the host's card has no
  fixed name. In plain words: *this account may reconfigure the IPv4 addressing of this machine.*
  No `iptables` is involved, no NAT, and no IPv6 (not handled at all).

Wi-Fi is refused (an access point will not answer several MAC addresses behind one association),
as is a card already enslaved to somebody else's bridge, or an ambiguous default route.

### 7.3 Granting (b) without (c)

That is the **default**, and nothing has to be done for it: a bare `install` grants (a) only, and
neither bridge block is ever granted at install time. When a user starts a bridge component,
Marionnet asks for **their own sudo password** and installs that block — so (c) is already reserved
to accounts that may sudo at run time, long after the administrator's installation.

To hand a classroom the NAT bridge in advance, without anybody being asked for a password and
without (c) ever entering the picture:

```bash
sudo marionnet-sudoers.sh install --enable-natbridge %marionnet
```

and, symmetrically, to take one block back while leaving the socle alone:

```bash
sudo marionnet-sudoers.sh uninstall --disable-lanbridge      # every account
sudo marionnet-sudoers.sh uninstall --disable-lanbridge <user>
```

### 7.4 Forbidding a block outright

Taking a grant back does not prevent the next user from asking for it again, from the interface,
with their own password. An administrator who does not want a LAN bridge built on this machine —
ever, by anybody — says so once:

```bash
sudo marionnet-sudoers.sh deny --lanbridge     # or --natbridge, or --bridges
```

While that veto is in place: the block is refused to everybody, the grant already in place is
**taken back** (leaving it would make the veto a lie), and Marionnet **says so in its interface
instead of asking for a password**. Lift it with `sudo marionnet-sudoers.sh allow --lanbridge` —
which grants nothing: a user still has to ask. Anybody may check the current state, no privilege
needed:

```bash
marionnet-sudoers.sh policy          # exit 0 if allowed, 3 if denied; says which
```

The veto is a file in `/etc/marionnet/`, world-readable on purpose: Marionnet has to know the
answer *before* asking for a password, and a file in `/etc/sudoers.d/` is 0440 root, as it must be.

The socle — block (a) — has **no** veto: the administrator grants it by hand, so forbidding it
would be not typing the command. And a veto stops a **mistake**, not a determined administrator,
who edits `/etc/sudoers.d/` directly. Where it bites is the common classroom setup — a teacher who
may sudo, students who may not — and that is exactly where a LAN bridge gets built by accident.

### 7.5 Launching it, and checking the installation

```bash
marionnet                    # or: marionnet -r lab.mar, marionnet --exam, marionnet --help
```

`marionnet` is the name every page of this documentation types — the teacher's guide, the exam
mode, the control-channel examples, the lab scripts. It is a symlink to `marionnet.native`, the
name `dune install` gives the executable: the same program, under the name a human uses.

Two commands answer *"is this installation the one I think it is?"*, whichever method installed
it:

```bash
marionnet -v                 # version and revision
marionnet --paths            # where this installation looks for images, kernels and scripts
```

`--paths` is the answer to *"the images do not appear"*: it prints the directories the
configuration cascade actually resolved to (§ 5).

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
| Marionnet starts but the guest images do not appear | they were laid down under a prefix the application does not read — § 5, then `marionnet --paths` |
| *Unsatisfied dependency* at startup | `vde2`, `graphviz` or `uml-utilities` is missing; the tarball's `install.sh` names what is missing, `--with-deps` installs it |
| a virtual machine will not start, taps cannot be built | the sudoers rule — § 7 |
| nothing opens when a guest starts `wireshark` or `xterm` | block (a) is not granted (§ 7.2), or the host has no X display |

## Where to go next

These pages are installed beside this one. They live in `doc-src/` of the source repository, which
is also where the archive key of § 2 and § 3 is published:

```bash
git clone https://git.launchpad.net/marionnet
```

| Page | Read it for |
|---|---|
| `INSTALL.FR.md` | this same page in French |
| `teacher-guide.md` | preparing a lab, running the session, marking it |
| `scripting/README.md` | driving Marionnet from a script, through the control channel |
| `exam-mode.md` | what an exam session records |
| `project-format-v3.md` | the `.mar` project format |
