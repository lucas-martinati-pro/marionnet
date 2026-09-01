#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Make the release directory readable BY DNF: write the repodata/ a yum repository is made
# of, beside the .rpm that Makefile.d/release.rpm.sh published there. The exact counterpart
# of Makefile.d/release.apt.sh, and it inherits its three decisions unchanged.
#
# A FLAT repository, like the apt one and for the same reason: a release of Marionnet is
# ALREADY one directory per series (download/marionnet-install.sh/1.0.x/), holding the guest
# images, the kernels, the precompiled tarball, the .deb and the .rpm. The series IS the
# repository; a tree of subdirectories would put the same files at a second place under a
# second name. One stanza reaches it:
#
#     [marionnet-1.0.x]
#     name=Marionnet 1.0.x
#     baseurl=https://www.marionnet.org/download/marionnet-install.sh/1.0.x/
#     enabled=1
#     gpgcheck=0
#
# WHAT THIS BUYS, and it is not a convenience: with the repository, `dnf install marionnet'
# resolves vde2 and uml-utilities FROM THIS SAME DIRECTORY. Without it, the two dependencies
# no RPM distribution carries (episode 17) have to be named on the command line by whoever
# installs -- which means knowing they exist, and why. A repository is the only form in which
# "Marionnet needs a vde2 nobody packages" stops being the user's problem.
#
# THREE CATALOGUES NOW COHABIT IN THAT DIRECTORY, and none derives from the others:
#   SHA256SUMS  what bin/scripts/marionnet-install.sh reads -- names and digests of the
#               ARTEFACTS (images, kernels, tarball, and the packages it lists and ignores);
#   Packages    what apt reads -- the control fields of the .deb only;
#   repodata/   what dnf reads -- the headers of the .rpm only.
# SHA256SUMS knows nothing of a Requires:, and repodata knows nothing of a 5 GiB image.
#
# THE INDEXES ARE NOT ARTEFACTS, so repodata/ is NOT recorded in SHA256SUMS -- the same three
# reasons as on the apt side, the first alone being enough: it is rewritten every time a
# package is published, so a digest recorded for it would go stale by itself (the failure
# episode 9b had to repair). dnf carries its own integrity in repomd.xml, which is also the
# only file a signature would ever attach to.
#
# UNSIGNED, TODAY, hence `gpgcheck=0' in the stanza above -- the counterpart of the
# `[trusted=yes]' the apt line needs. Signing is the question of the SERVER episode: it
# decides the key, and inventing one here would be inventing the answer.
#
# createrepo_c RUNS IN A CONTAINER, for the same reason rpmbuild does (episode 17): it is the
# tool of an RPM distribution, and the release machine is not one. Nothing is installed here.
#
# No bashbricks here, on purpose: like the six publishers it joins, this script sources
# nothing.
#
# Usage: Makefile.d/release.dnf.sh [OPTIONS]
#
#   -o, --output-dir DIR         the release directory to index
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#       --base-url URL           also write a ready-to-use marionnet.repo naming this URL
#                                (default: none -- the stanza is printed instead, since the
#                                URL of a directory is only known once it is served)
#       --build-image IMAGE      the distribution createrepo_c runs in (default: fedora:42)
#   -c, --check                  say what the index holds, write nothing
#   -h, --help                   this help
# ---

set -euo pipefail

# The index is public data: 0644, whatever the packager's umask is (usually 002).
umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

function info { echo "==> $*"; }
function warn { echo "==> WARNING: $*" >&2; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
  sed -n '/^# Usage: Makefile.d/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

# The series rule lives in the script which owns it, and is asked of it -- as in the six
# sibling publishers -- rather than computed a second time here.
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

SERIES=""
OUTDIR=""
BASE_URL=""
SIGN_KEY=""             # `@published' until resolved against the keyring below
KEYRING_ASC="$ROOT/marionnet-archive-keyring.asc"   # the archive's identity, versioned in git
# WHERE A CLIENT FETCHES THE PUBLIC KEY, and it is deliberately not this repository: the key is
# versioned in git, hence served by Launchpad -- another infrastructure than the one serving
# the packages (episode 30).
#
# BUT THE STANZA BELOW DOES NOT NAME THIS URL, and that is a measurement, not a preference:
# `gpgkey=' is fetched by dnf, and dnf follows redirects. git.launchpad.net answers 302 towards
# its OpenID login page about one request in six (episode 30 bis), so dnf downloads the 26-byte
# login page and the transaction dies with `Failed to import OpenPGP keys into temporary
# keyring: Compute cert len failed' -- measured 3 failures in 8 installations, each of them
# AFTER 188 MiB of packages had been downloaded. Where curl can be told not to follow (and the
# INSTALL page forbids `-L' for exactly this reason), dnf cannot.
#
# So the key is handed over the way § 2 of the INSTALL page hands it to apt: fetched by the
# reader, checked against the fingerprint, and named as a LOCAL file. That also restores the
# discipline the URL had quietly removed -- a key dnf fetches by itself is a key nobody looked at.
KEY_URL="https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc"
# The conventional place for a distribution's archive keys; the INSTALL page puts it there.
KEY_LOCAL="/etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet"
BUILD_IMAGE="fedora:42"
CHECK=0

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    --base-url)      BASE_URL="$2"; shift 2 ;;
    --sign)          if test $# -ge 2 && case "$2" in -*) false ;; *) test -n "$2" ;; esac
                     then SIGN_KEY="$2"; shift 2
                     else SIGN_KEY="@published"; shift 1
                     fi ;;
    --build-image)   BUILD_IMAGE="$2"; shift 2 ;;
    -c|--check)      CHECK=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown option '$1' (try --help)" ;;
  esac
done

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

shopt -s nullglob
RPMS=("$OUTDIR"/*.rpm)
shopt -u nullglob

REPO_ID="marionnet-$SERIES"

if ((CHECK)); then
  if test -f "$OUTDIR/repodata/repomd.xml"; then
    info "$OUTDIR/repodata announces:"
    # primary.xml.gz is the file dnf reads first; the package names and versions are read
    # back out of it rather than out of the .rpm, so that this really says what the INDEX
    # holds -- which is the only thing a client will see.
    primary=$(ls "$OUTDIR"/repodata/*primary.xml* 2>/dev/null | head -1)
    if test -n "$primary"; then
      case "$primary" in
        *.gz)  zcat -- "$primary" ;;
        *.zst) command -v zstd >/dev/null && zstd -dc -- "$primary" || echo "" ;;
        *)     cat -- "$primary" ;;
      esac | sed -n 's/.*<name>\([^<]*\)<\/name>.*/\1/p;s/.*<version epoch="[^"]*" ver="\([^"]*\)" rel="\([^"]*\)".*/    \1-\2/p' | paste - - 2>/dev/null | sed 's/^/    /'
    fi
  else
    info "no repodata in $OUTDIR: this release is not readable by dnf yet"
  fi
  info "${#RPMS[@]} .rpm in the directory"
  test -f "$OUTDIR/marionnet.repo" && info "marionnet.repo is there" || info "no marionnet.repo"
  exit 0
fi

((${#RPMS[@]})) || die "no .rpm in $OUTDIR: run \`make release-rpm' first"

command -v docker >/dev/null || die "\`docker' not found (createrepo_c runs in a container)"

info "release dir  : $OUTDIR"
info "packages     : ${#RPMS[@]}"

# ---
# --- The box createrepo_c runs in.
# ---
# Its own image, and not the one release.rpm.sh builds: the two scripts publish into the same
# directory but neither calls into the other's internals, which is what lets either be run
# alone on a machine where the other never ran.
# ---
BUILDER_IMAGE="mrn-rpm-repo-$(echo "$BUILD_IMAGE" | tr ':/' '--')"

if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
  info "building the createrepo box $BUILDER_IMAGE (once) ..."
  CTX=$(mktemp -d -- "${TMPDIR:-/tmp}/marionnet-release-dnf.XXXXXXXX")
  trap 'rm -rf -- "$CTX"' EXIT
  cat > "$CTX/Dockerfile" <<EOF
FROM $BUILD_IMAGE
RUN dnf -y install createrepo_c && dnf clean all
EOF
  docker build -q -t "$BUILDER_IMAGE" -- "$CTX" >/dev/null || \
    die "could not build the createrepo box from $BUILD_IMAGE"
fi

# ---
# --- repodata/.
# ---
# --update would reuse the previous index for packages whose name and mtime did not change;
# it is NOT used, because the one case where that matters is exactly the one which must not
# be got wrong -- a package REPUBLISHED under the same name, which episode 9b measured on the
# apt side as a catalogue quietly describing the previous file. The index of a release
# directory is cheap to write whole (five packages), so it is written whole.
#
# Run as root in the box like rpmbuild is, then given back to the caller: repodata/ appears
# in a directory belonging to the packager, who must be able to publish and remove it.
docker run --rm -v "$OUTDIR:/repo" -w /repo "$BUILDER_IMAGE" bash -c '
  createrepo_c --quiet . && chown -R "$1:$2" repodata
' -- "$(id -u)" "$(id -g)" || die "createrepo_c failed"

info "written: repodata/ ($(ls "$OUTDIR/repodata" | wc -l) files)"

# ---
# --- The signature of the index (episode 30b).
# ---
# repomd.xml.asc is to `repo_gpgcheck=1' what InRelease is to apt: the file which says that
# the index of this repository comes from whoever holds the archive key. Written HERE, by the
# script which writes repodata/, for the reason established at episode 30 -- a signature is
# void the moment the file it signs changes, so it belongs to whoever writes that file.
#
# It signs the INDEX only. What vouches for each package is the signature rpmsign put inside
# it (release.rpm.sh --sign), which is a different mechanism from apt's: there, one signature
# on Release chains down to every package by digest; here, rpm verifies each package on its
# own. Both are needed, which is why `gpgcheck=1' and `repo_gpgcheck=1' appear together below.
#
# Not in SHA256SUMS, like repodata/ itself: rewritten at every publication, so a digest
# recorded for it would go stale on its own (the defect of episode 9b).
if test -n "$SIGN_KEY"; then
  command -v gpg >/dev/null || die "\`gpg' not found, but --sign was asked"
  if test "$SIGN_KEY" = "@published"; then
    test -f "$KEYRING_ASC" \
      || die "--sign was given alone, but $KEYRING_ASC does not exist: nothing says who this archive is"
    SIGN_KEY=$(gpg --with-colons --show-keys -- "$KEYRING_ASC" 2>/dev/null \
               | awk -F: '$1=="fpr" {print $10; exit}')
    test -n "$SIGN_KEY" || die "cannot read a fingerprint out of $KEYRING_ASC"
  fi
  gpg --list-secret-keys -- "$SIGN_KEY" >/dev/null 2>&1 || die "no secret key '$SIGN_KEY' in this keyring"
  if test -f "$KEYRING_ASC"; then
    published=$(gpg --with-colons --show-keys -- "$KEYRING_ASC" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')
    signing=$(gpg --with-colons --list-secret-keys -- "$SIGN_KEY" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')
    test "$published" = "$signing" \
      || die "the signing key ($signing) is not the one the sources publish ($published)"
  fi
  # The signature of the PREVIOUS index goes first, and only then is a new one attempted:
  # createrepo has just rewritten repomd.xml, so what sits beside it signs a file which no
  # longer exists. Should the signature fail here -- no pinentry, wrong passphrase, key gone --
  # dying with that file still in place would leave a repository which claims to be signed and
  # is not, which is the one outcome worse than an unsigned one.
  rm -f -- "$OUTDIR/repodata/repomd.xml.asc"
  gpg --batch --yes --default-key "$SIGN_KEY" --armor --detach-sign \
      -o "$OUTDIR/repodata/repomd.xml.asc.new" -- "$OUTDIR/repodata/repomd.xml" \
    || die "signing failed (repomd.xml.asc): the stale signature was removed, this directory is now unsigned"
  mv -f -- "$OUTDIR/repodata/repomd.xml.asc.new" "$OUTDIR/repodata/repomd.xml.asc"
  info "signed: repodata/repomd.xml.asc  (key $SIGN_KEY)"
else
  # A repository which STOPS being signed is worse than one which never was: every machine
  # already carrying repo_gpgcheck=1 would refuse it. So a signature of a previous index goes.
  if test -f "$OUTDIR/repodata/repomd.xml.asc"; then
    rm -f -- "$OUTDIR/repodata/repomd.xml.asc"
    warn "removed a STALE repomd.xml.asc: it signed a previous index (re-run with \`--sign')"
  fi
fi

# ---
# --- marionnet.repo, only if we were told where this directory will live.
# ---
# The URL of a release directory is not knowable here -- it is decided when the directory is
# served -- so this file is written only when --base-url says it, and the stanza is merely
# printed otherwise. Writing a file with a guessed URL would publish a repository which
# points at nothing, and a client would blame the server for it.
# ---
if test -n "$BASE_URL"; then
  # The stanza states what this run actually did, and never what it wishes were true: a .repo
  # asking for gpgcheck on an unsigned repository would make dnf refuse everything.
  if test -n "$SIGN_KEY"; then
    cat > "$OUTDIR/marionnet.repo.new" <<EOF
[$REPO_ID]
name=Marionnet $SERIES
baseurl=$BASE_URL
enabled=1
# Signed (episode 30b). gpgcheck verifies EACH PACKAGE, repo_gpgcheck verifies the index
# (repomd.xml.asc) -- two mechanisms, unlike apt where one signature on Release chains down
# to the packages by digest.
#
# The key is a LOCAL file, put there by you, and it comes from the SOURCES and not from this
# repository: a key travelling beside the packages it signs proves no more than https already
# does. Fetch it and check its fingerprint before installing anything -- see § 3 of the INSTALL
# page, or:
#   sudo curl -o $KEY_LOCAL \\
#        $KEY_URL
#   gpg --show-keys $KEY_LOCAL
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://$KEY_LOCAL
EOF
  else
    cat > "$OUTDIR/marionnet.repo.new" <<EOF
[$REPO_ID]
name=Marionnet $SERIES
baseurl=$BASE_URL
enabled=1
# Unsigned: this directory was indexed without \`--sign' (see Makefile.d/release.dnf.sh).
gpgcheck=0
EOF
  fi
  mv -f -- "$OUTDIR/marionnet.repo.new" "$OUTDIR/marionnet.repo"
  info "written: marionnet.repo (baseurl $BASE_URL)"
  info "A machine adds it with:"
  if test -n "$SIGN_KEY"; then
    # The key FIRST: the stanza names a local file, so a machine which fetched the .repo and
    # nothing else would be told the key is missing -- before downloading anything, at least.
    info "  sudo curl -o $KEY_LOCAL $KEY_URL"
    info "  gpg --show-keys $KEY_LOCAL     # compare with the published fingerprint"
  fi
  info "  sudo curl -o /etc/yum.repos.d/marionnet.repo ${BASE_URL%/}/marionnet.repo"
  info "  sudo dnf install marionnet"
else
  info "no --base-url given, so no marionnet.repo was written. The stanza to serve is:"
  if test -n "$SIGN_KEY"; then
    printf '      [%s]\n      name=Marionnet %s\n      baseurl=<url-of-this-directory>\n      enabled=1\n      gpgcheck=1\n      repo_gpgcheck=1\n      gpgkey=file://%s\n' \
           "$REPO_ID" "$SERIES" "$KEY_LOCAL"
    info "  (and the key itself is fetched, once, from $KEY_URL)"
  else
    printf '      [%s]\n      name=Marionnet %s\n      baseurl=<url-of-this-directory>\n      enabled=1\n      gpgcheck=0\n' \
           "$REPO_ID" "$SERIES"
  fi
fi

info "done. \`dnf install marionnet' now resolves vde2 and uml-utilities from this directory."
