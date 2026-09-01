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

# Put a release directory on www.marionnet.org, and give the two package managers a URL
# which does not move when the series does.
#
# This is the SEVENTH script of the family, and the first which is not a publisher: the six
# others MAKE a release directory (an image, a kernel, the binary tarball, SHA256SUMS, the
# .deb + Packages/Release, the .rpm + repodata/), this one only CARRIES it. The distinction
# is the design rule of the whole file: THIS SCRIPT WRITES NOTHING INTO A RELEASE DIRECTORY.
# Every file it deposits has exactly one writer elsewhere, and adding a second one here is
# how two catalogues start to disagree (episode 8) or how an index goes stale under a digest
# recorded for it (episode 9b). The single exception is the SIGNATURE, and the header below
# says why it is not an exception at all.
#
# THE CATALOGUE DECIDES WHAT GOES UP -- the exact counterpart of the episode 8 invariant.
# `SHA256SUMS' is not an integrity file which happens to list names, it IS the list of what
# a release is made of, and this script uploads that list and nothing else. It matters here
# more than anywhere: a release directory also holds the publisher's WORKING STATE -- the
# raw guest images and their .conf, from which the tarballs were built. Measured on the
# 1.0.x directory of 2026-08-31: 11 GiB on disk, of which the catalogue names 3.8 GiB. The
# 7.3 GiB left are the raw images (machine-debian-trixie-39212 alone is 5.4 GiB), which no
# consumer ever fetches -- the installer downloads tarballs -- and which would not even fit:
# the server has 15 GiB free. Uploading `the release directory' would therefore have failed,
# and failed halfway.
#
# rsync, not the `tar cf - | ssh tar -xf -' of the ancestor
# (useful-scripts/BACKUP/marionnet_from_scratch.install_on_site). Two reasons the ancestor
# did not have: a release is now 3.8 GiB across a ProxyJump, so an interrupted deposit must
# resume instead of starting over; and republication is idempotent BY NAME (episode 8), so
# what is already there and identical must not be sent again. A truncated artefact under the
# RIGHT name would be the worst outcome of all -- the installer would fetch it, find the
# digest in disagreement and remove it, reporting a corruption which is really an interrupted
# upload. What rules that out is not `--partial-dir' but rsync itself: it writes under a
# temporary name and renames only at the end. `--partial-dir' adds the RESUME, and only when
# the receiver is given time to file its partial away -- an abrupt drop of the connection is
# not (measured: a deliberate interruption left a 150 MiB `.<name>.XXXXXX' in place, to be
# removed by hand). Say it that way round: the guarantee holds without the option, the resume
# is what the option buys, and it is conditional.
#
# -rlt and NOT -a. `-a' implies -pgo, which asks to preserve the packager's mode, owner and
# group on a machine where that user does not exist; the files are public data, so the modes
# are stated instead (--chmod). `-t' is kept, and it is not cosmetic: it is what makes the
# Apache listing -- the FALLBACK catalogue of the installer, episode 8 -- tell the truth
# about when an artefact was published.
#
# THE PROOF IS TAKEN ON THE SERVER, not here: after the transfer, `sha256sum -c SHA256SUMS'
# is run in the remote directory. The catalogue travelled with the artefacts, so the same
# file which said what to upload says whether it arrived -- and the check costs no bandwidth
# at all, since the server reads its own disk. This is the measurement the episode exists
# for; a transfer which reports success is not a deposit which is intact.
#
# EXTRAS ARE NAMED, NEVER REMOVED. A file which is on the server and not in the catalogue is
# reported and left alone; `--prune' removes it, and only when asked. Same posture as the
# mtime guard of episode 23: name the remedy rather than apply it. `rsync --delete' as a
# default would silently drop an older release someone put there on purpose.
#
# TWO STABLE ENTRY POINTS, because a sources.list line is pinned to the series. Episode 13
# noted the defect: `deb ... /download/marionnet-install.sh/1.0.x/ ./' names a series, so
# opening 1.1.x would mean editing every machine which ever installed Marionnet. The fix is
# a symlink the server owns -- /download/apt and /download/rpm, both pointing at the current
# series -- so that moving to a new series is one `ln -sfn' here and nothing at all out
# there. Apache follows symlinks on this host (measured: /download/Marionnet.ova is one and
# is served). They point at the SAME directory, and that is not a duplicate: three
# catalogues cohabit in it (SHA256SUMS, Packages, repodata/ -- episode 18), so the one
# directory really is both repositories; only the vocabulary of the reader differs.
#
# THE INSTALLER SCRIPT IS PUBLISHED UNDER BOTH ITS NAMES. bin/scripts/marionnet-install.sh
# decides what it is by looking at $0 (episode 16): under the name `marionnet-get-images' it
# is the image chooser, and it refuses --binary. Publishing one name only would make the
# documented `marionnet-get-images' command unobtainable -- a user who saves the file under
# that name gets the chooser, but nobody would know to. It goes to the PARENT of the series
# directory, where the ancestor's `marionnet_from_scratch' still sits: it is the one file
# whose URL must survive every series.
#
# SIGNING: WIRED, NOT ARMED, and the reason is not laziness. `--sign KEYID' produces the
# InRelease and Release.gpg apt wants, and without it the repository stays [trusted=yes] --
# which is what release.apt.sh writes today and what 33 green cases measured (episode 15b).
# Deciding to sign is deciding three things, and only the first is code:
#   1. the signature itself -- the ten lines below, exercised against a throwaway key;
#   2. the CUSTODY of the private key: a key generated on a development laptop, without a
#      passphrase, so that a script can use it unattended, protects nothing it claims to;
#   3. the DISTRIBUTION of the public key, which is the one that decides whether any of it
#      is worth anything. `signed-by=' is only a promise if the key reaches the user by some
#      channel OTHER than the repository it signs. Publishing the key next to the packages
#      and telling people to fetch it from there proves exactly what https already proves --
#      that the server was not impersonated -- and nothing about whoever wrote the packages.
# Points 2 and 3 are not questions about this script, so they are not settled by it. Note
# that the signature is nevertheless OURS to write, and this does not break the one-writer
# rule of the header: Release says what the repository CONTAINS and belongs to the indexer,
# Release.gpg says WHO VOUCHES for it and belongs to whoever deposits -- this script.
#
# No bashbricks here, on purpose: like the six publishers it joins, this script sources
# nothing.
#
# Usage: Makefile.d/upload.www.marionnet.org.sh [OPTIONS]
#
#   -o, --output-dir DIR         the release directory to deposit
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#       --host HOST              ssh destination (default: marionnet, from ~/.ssh/config)
#       --remote-root DIR        the served download/ directory on that host
#                                (default: /home/marionnet/site/download)
#   -n, --dry-run                say what would be sent and changed, send nothing
#   -c, --check                  compare the server with the catalogue, upload nothing
#       --prune                  also remove what is on the server and not in the catalogue
#       --no-entry-points        do not touch the download/apt and download/rpm symlinks
#       --no-script              do not publish bin/scripts/marionnet-install.sh
#       --sign KEYID             sign Release with this gpg key (InRelease + Release.gpg)
#   -h, --help                   this help
# ---

set -euo pipefail

# What we deposit is public data: 0644 for files, 0755 for directories, whatever the
# packager's umask is (usually 002). Stated to rsync rather than inherited.
umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

function info { echo "==> $*"; }
function warn { echo "==> WARNING: $*" >&2; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
  sed -n '/^# Usage: Makefile.d/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

# The series rule lives in the script which owns it, and is asked of it -- as in the five
# sibling publishers -- rather than computed a second time here.
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

SERIES=""
OUTDIR=""
HOST="marionnet"
REMOTE_ROOT="/home/marionnet/site/download"
DRYRUN=0
CHECK=0
PRUNE=0
ENTRY_POINTS=1
PUBLISH_SCRIPT=1
SIGN_KEY=""

while (($#)); do
  case "$1" in
    -o|--output-dir)    OUTDIR="$2"; shift 2 ;;
    -s|--series)        SERIES="$2"; shift 2 ;;
       --host)          HOST="$2"; shift 2 ;;
       --remote-root)   REMOTE_ROOT="${2%/}"; shift 2 ;;
    -n|--dry-run)       DRYRUN=1; shift ;;
    -c|--check)         CHECK=1; shift ;;
       --prune)         PRUNE=1; shift ;;
       --no-entry-points) ENTRY_POINTS=0; shift ;;
       --no-script)     PUBLISH_SCRIPT=0; shift ;;
       --sign)          SIGN_KEY="$2"; shift 2 ;;
    -h|--help)          usage; exit 0 ;;
    *)                  die "unknown option '$1' (try --help)" ;;
  esac
done

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

command -v rsync >/dev/null || die "\`rsync' not found (package rsync)"

CATALOGUE="$OUTDIR/SHA256SUMS"
test -f "$CATALOGUE" || die "no SHA256SUMS in $OUTDIR: run \`make release.sha256sums' first"

# The remote layout, derived once. The series directory sits under the same name the
# ancestor used for its own script -- download/marionnet-install.sh/ -- so that the parent
# holds the entry-point script and the children hold the series.
REMOTE_BASE="$REMOTE_ROOT/marionnet-install.sh"
REMOTE_DIR="$REMOTE_BASE/$SERIES"

# ONE ssh connection for the whole run, shared by every call and by rsync. A deposit makes
# a good dozen short calls (mkdir, the transfer, two symlinks, the remote sha256sum, the
# listing, the pruning), and this server is reached THROUGH A JUMP HOST: a burst of
# short-lived connections is what a jump host defends against, and it defended (measured on
# 2026-09-01: `kex_exchange_identification: Connection reset by peer', then a back-off of
# several minutes during which nothing could reach the server at all). A master connection
# also makes the run faster, each call no longer paying a handshake through the jump.
# The socket path is kept SHORT on purpose: a unix socket path is capped near 104 bytes, and
# the scratch directories of this project are much longer than that.
SSH_CTL="/tmp/mrn-ssh-$$"
SSH_OPTS=(-o BatchMode=yes -o ControlMaster=auto -o "ControlPath=$SSH_CTL" -o ControlPersist=120)
function ssh_do { ssh "${SSH_OPTS[@]}" -- "$HOST" "$@"; }
# ONE trap for the whole script: bash keeps a single EXIT handler, so a later `trap ... EXIT'
# would silently replace this one and leave the master connection open.
TMPFILES=()
function cleanup {
  ((${#TMPFILES[@]})) && rm -f -- "${TMPFILES[@]}"
  ssh -O exit -o "ControlPath=$SSH_CTL" -- "$HOST" 2>/dev/null || true
}
trap cleanup EXIT

# ---
# --- What the catalogue names, and whether we have it all.
# ---
# The names are read with `cut -c67-' rather than awk on $2: a sha256sum line is a 64-char
# digest, two spaces and THE REST OF THE LINE, so a name containing a space survives here
# and would not survive a field split. None does today; the day one does, this must not be
# the place which loses it silently.
mapfile -t CATALOGUED < <(cut -c67- -- "$CATALOGUE")
((${#CATALOGUED[@]})) || die "SHA256SUMS is empty in $OUTDIR"

MISSING=()
for f in "${CATALOGUED[@]}"; do
  test -e "$OUTDIR/$f" || MISSING+=("$f")
done
if ((${#MISSING[@]})); then
  printf '%s: catalogued but absent from %s:\n' "$0" "$OUTDIR" >&2
  printf '    %s\n' "${MISSING[@]}" >&2
  die "the catalogue announces ${#MISSING[@]} artefact(s) which are not there (\`make release.sha256sums CHECK=1' says more)"
fi

# The index files, which are NOT in the catalogue (they are rewritten at every publication,
# so a digest recorded for them would go stale by itself -- episode 9b) and must travel
# nonetheless: without them the directory is a pile of files that neither apt nor dnf reads.
INDEXES=()
for f in SHA256SUMS Packages Packages.gz Release InRelease Release.gpg marionnet.repo repodata; do
  test -e "$OUTDIR/$f" && INDEXES+=("$f")
done

# BOTH FORMS OF THE SAME ARTEFACT: named before the transfer, not after it. The catalogue
# decides what goes up, so a redundancy in the catalogue becomes a redundancy in the deposit
# -- multiplied by the time it takes. Measured on 2026-08-31: the 1.0.x directory announced
# .tar.gz AND .tar.xz for four artefacts, 2.16 of the 3.87 GiB, and the deposit had to be
# interrupted an hour in. `xz' has been the default since episode 3 (factor 4, measured) and
# the installer falls back from one form to the other by itself, so the second form is dead
# weight on the wire. Named, not repaired: the catalogue has ONE writer, and it is not here.
BOTH_FORMS=()
for f in "${CATALOGUED[@]}"; do
  case "$f" in
    *.tar.gz) printf '%s\n' "${CATALOGUED[@]}" | grep -qxF "${f%.gz}.xz" && BOTH_FORMS+=("$f") ;;
  esac
done
if ((${#BOTH_FORMS[@]})); then
  warn "${#BOTH_FORMS[@]} artefact(s) are catalogued in BOTH forms; the .tar.gz doubles a .tar.xz:"
  printf '        %s\n' "${BOTH_FORMS[@]}" >&2
  warn "removing them from the release directory and re-running \`make release.sha256sums'"
  warn "retires their lines by itself -- the catalogue is never edited by hand."
fi

# SEVERAL REVISIONS OF THE SAME THING: named too, and for a reason the byte count hides.
# A release directory is not a build log. Measured on 2026-08-31, the day this script was
# written: it had accumulated 8 tarballs, 4 marionnet .deb and 5 marionnet .rpm -- one per
# episode of the day -- so `Packages' offered apt FOUR versions and `repodata/' offered dnf
# FIVE. Whoever typed `apt install marionnet=0~trunk+r913' would have got, quite legitimately,
# a build from BEFORE the episode 21 fix, and five of the eight tarballs were compiled here
# rather than in the floor box (glibc2.39), so they are refused on Debian 12 -- served for
# nothing. `--multiversion' in release.apt.sh exists so that one revision can REPLACE another
# without a gap, which is not the same thing as keeping every revision ever built.
# Named, not repaired: how many revisions a release keeps is not this script's decision.
function revision_of {  # <name> -> the r<N> it carries, or nothing
  local n="$1"
  case "$n" in
    marionnet_trunk-r*)      echo "${n#marionnet_trunk-r}"    | sed 's/_.*//' ;;
    marionnet_0~trunk+r*)    echo "${n#marionnet_0~trunk+r}"  | sed 's/_.*//' ;;
    marionnet-0~trunk+r*)    echo "${n#marionnet-0~trunk+r}"  | sed 's/-.*//' ;;
  esac
}
STALE=()
for pat in 'marionnet_trunk-r*' 'marionnet_0~trunk+r*' 'marionnet-0~trunk+r*'; do
  # shellcheck disable=SC2053
  mapfile -t fam < <(for f in "${CATALOGUED[@]}"; do [[ $f == $pat ]] && echo "$f"; done)
  ((${#fam[@]} > 1)) || continue
  newest=$(for f in "${fam[@]}"; do printf '%s\t%s\n' "$(revision_of "$f")" "$f"; done | sort -n | tail -1 | cut -f2)
  for f in "${fam[@]}"; do [[ $f != "$newest" ]] && STALE+=("$f"); done
done
if ((${#STALE[@]})); then
  warn "${#STALE[@]} superseded revision(s) of the application are catalogued:"
  printf '        %s\n' "${STALE[@]}" >&2
  warn "a release directory is not a build log, and both indexes offer every one of them."
  warn "remove them, then \`make release.sha256sums' + \`release-apt' + \`release-dnf', and"
  warn "deposit again with --prune."
fi

TOTAL_BYTES=$(cd -- "$OUTDIR" && du -cbL -- "${CATALOGUED[@]}" 2>/dev/null | tail -1 | cut -f1)

info "release dir  : $OUTDIR"
info "series       : $SERIES"
info "destination  : $HOST:$REMOTE_DIR"
info "catalogued   : ${#CATALOGUED[@]} artefacts ($(numfmt --to=iec --suffix=B "${TOTAL_BYTES:-0}"))"
info "indexes      : ${INDEXES[*]}"

# ---
# --- --check: compare the server with the catalogue, and say so. Uploads nothing.
# ---
if ((CHECK)); then
  if ! ssh_do "test -d '$REMOTE_DIR'" 2>/dev/null; then
    info "the server has no $REMOTE_DIR yet: this series was never deposited"
    exit 0
  fi
  info "verifying the deposit, on the server (it reads its own disk -- no bandwidth):"
  # The status is passed on rather than swallowed: --check is meant to be usable from another
  # script, and a check which always succeeds answers nothing.
  if ssh_do "cd '$REMOTE_DIR' && sha256sum -c --quiet SHA256SUMS"; then
    info "the server holds the catalogue, whole and intact"
    exit 0
  else
    warn "the server disagrees with its own catalogue (lines above)"
    exit 1
  fi
fi

# ---
# --- The local side is verified BEFORE anything leaves. One does not deposit what one has
# --- not checked: a digest taken here costs seconds and turns `the upload is corrupt' into
# --- a question with an answer.
# ---
if ((!DRYRUN)); then
  info "checking the release directory against its own catalogue..."
  ( cd -- "$OUTDIR" && sha256sum -c --quiet SHA256SUMS ) \
    || die "the release directory disagrees with its own SHA256SUMS -- nothing was sent"
fi

# ---
# --- The signature. See the header: it is ours to write, and it is not an index.
# ---
if test -n "$SIGN_KEY"; then
  command -v gpg >/dev/null || die "\`gpg' not found, but --sign was asked"
  test -f "$OUTDIR/Release" || die "no Release to sign in $OUTDIR (run \`make release-apt')"
  gpg --list-secret-keys -- "$SIGN_KEY" >/dev/null 2>&1 \
    || die "no secret key '$SIGN_KEY' in this keyring -- see the header on custody and distribution"
  if ((DRYRUN)); then
    info "would sign Release with $SIGN_KEY (InRelease, Release.gpg)"
  else
    info "signing Release with $SIGN_KEY"
    # Both forms, because apt takes either and old apt only takes the detached one:
    # InRelease is Release with the signature wrapped around it, Release.gpg is the
    # signature alone, beside the file it signs. --yes: a re-deposit re-signs.
    gpg --batch --yes --default-key "$SIGN_KEY" --clearsign  -o "$OUTDIR/InRelease"   -- "$OUTDIR/Release"
    gpg --batch --yes --default-key "$SIGN_KEY" --armor --detach-sign -o "$OUTDIR/Release.gpg" -- "$OUTDIR/Release"
    for f in InRelease Release.gpg; do
      printf '%s\n' "${INDEXES[@]}" | grep -qx "$f" || INDEXES+=("$f")
    done
  fi
fi

# marionnet.repo, if it is there, must name the STABLE entry point and not the series
# directory -- otherwise dnf users are pinned exactly where episode 13 said not to pin apt
# users. Named, not repaired: its writer is release.dnf.sh, and this script writes nothing
# into a release directory.
if test -f "$OUTDIR/marionnet.repo" && ! grep -qi 'download/rpm' "$OUTDIR/marionnet.repo"; then
  warn "marionnet.repo names the series directory, not the stable entry point; consider:"
  warn "  make release-dnf BASE_URL=https://www.marionnet.org/download/rpm/"
fi

# ---
# --- The transfer.
# ---
LIST=$(mktemp); TMPFILES+=("$LIST")
printf '%s\n' "${CATALOGUED[@]}" "${INDEXES[@]}" > "$LIST"

RSYNC_OPTS=(-rlt --chmod=D755,F644 --human-readable --partial-dir=.rsync-partial
            --files-from="$LIST" --info=stats1,progress2
            -e "ssh ${SSH_OPTS[*]}")
((DRYRUN)) && RSYNC_OPTS+=(--dry-run --itemize-changes)

info "sending $(($(wc -l < "$LIST"))) paths..."
# Guarded: --dry-run must leave the server exactly as it found it, and `mkdir -p\' on a
# directory which does not exist yet is a change like any other. Measured the hard way --
# the first dry run of this script created the series directory it was only pretending to
# fill, and rsync then reported a destination which the run itself had made.
((DRYRUN)) || ssh_do "mkdir -p -- '$REMOTE_DIR'"
rsync "${RSYNC_OPTS[@]}" -- "$OUTDIR/" "$HOST:$REMOTE_DIR/"

# ---
# --- The entry-point script, under both of its names (episode 16).
# ---
if ((PUBLISH_SCRIPT)); then
  SRC="$ROOT/bin/scripts/marionnet-install.sh"
  test -f "$SRC" || die "no such file: $SRC"
  info "publishing the installer under both its names, in $REMOTE_BASE"
  if ((DRYRUN)); then
    info "would send $SRC -> $REMOTE_BASE/marionnet-install.sh (0755)"
    info "would link marionnet-get-images -> marionnet-install.sh"
  else
    rsync -lt --chmod=F755 -e "ssh ${SSH_OPTS[*]}" -- "$SRC" "$HOST:$REMOTE_BASE/marionnet-install.sh"
    # The second name is a symlink and not a copy: two copies of a script which decides what
    # it is by looking at $0 are two things to keep in step, and Apache serves the target of
    # a symlink (measured on this host).
    ssh_do "ln -sfn -- marionnet-install.sh '$REMOTE_BASE/marionnet-get-images'"
  fi
fi

# ---
# --- The two stable entry points. See the header.
# ---
if ((ENTRY_POINTS)); then
  info "pointing download/apt and download/rpm at the $SERIES series"
  if ((DRYRUN)); then
    info "would link $REMOTE_ROOT/{apt,rpm} -> marionnet-install.sh/$SERIES"
  else
    # Relative targets: the symlink must keep meaning if the site tree is ever moved or
    # copied, and an absolute /home/marionnet/... inside the document root would also
    # publish the server's home directory in the listing.
    ssh_do "cd -- '$REMOTE_ROOT' && ln -sfn -- 'marionnet-install.sh/$SERIES' apt && ln -sfn -- 'marionnet-install.sh/$SERIES' rpm"
  fi
fi

# ---
# --- The proof, taken on the server.
# ---
if ((!DRYRUN)); then
  info "verifying the deposit, on the server:"
  ssh_do "cd '$REMOTE_DIR' && sha256sum -c --quiet SHA256SUMS" \
    || die "the deposit does not match the catalogue it travelled with"
  info "the server holds the ${#CATALOGUED[@]} catalogued artefacts, whole and intact"
fi

# The partial directory rsync leaves behind: litter, not content, and it survives a clean run
# because rsync only removes it when it has something to move out of it. Removed if empty --
# this is the one thing on the server this script owns, since it is the one thing it created.
((DRYRUN)) || ssh_do "rmdir -- '$REMOTE_DIR/.rsync-partial' 2>/dev/null" || true

# ---
# --- What is up there and not in the catalogue. Named, never removed (unless asked).
# ---
KNOWN=$(mktemp); TMPFILES+=("$KNOWN")
printf '%s\n' "${CATALOGUED[@]}" "${INDEXES[@]}" .rsync-partial | sort -u > "$KNOWN"
EXTRAS=()
if ((!DRYRUN)); then
  mapfile -t EXTRAS < <(ssh_do "cd '$REMOTE_DIR' && ls -1A" | sort -u | comm -13 "$KNOWN" -)
fi

if ((${#EXTRAS[@]})); then
  warn "${#EXTRAS[@]} file(s) on the server are not in the catalogue:"
  printf '        %s\n' "${EXTRAS[@]}" >&2
  if ((PRUNE)) && ((!DRYRUN)); then
    info "--prune: removing them"
    # ONE ssh call for the whole list, not one per file. Measured the hard way on 2026-09-01:
    # a loop opening 17 connections in a row through the jump host was rate-limited and reset
    # (`kex_exchange_identification: Connection reset by peer'), half way through the removal.
    # A jump host is a shared resource, and a burst of short-lived connections looks exactly
    # like what it defends against.
    #
    # printf %q, not a pair of quotes: these names come from `ls\' on the server, so they are
    # data, and a name holding a quote would otherwise end the string and let the rest of it
    # be read as a command -- by an `rm -rf\' running there.
    PRUNE_ARGS=""
    for f in "${EXTRAS[@]}"; do PRUNE_ARGS+=" $(printf %q "$REMOTE_DIR/$f")"; done
    ssh_do "rm -rf --$PRUNE_ARGS"
  else
    warn "they are left alone; \`--prune' removes them"
  fi
fi

# ---
# --- What a user has to type, with the URLs this deposit just created.
# ---
URL="https://www.marionnet.org/download"
echo
((DRYRUN)) && info "nothing was sent. Once deposited, the three ways in:" \
           || info "deposited. The three ways in:"
echo "    # the installer, series-independent:"
echo "    wget $URL/marionnet-install.sh/marionnet-install.sh && bash marionnet-install.sh --help"
echo
echo "    # apt (the entry point follows the series, the line does not):"
echo "    echo 'deb [trusted=yes] $URL/apt/ ./' | sudo tee /etc/apt/sources.list.d/marionnet.list"
echo "    sudo apt update && sudo apt install marionnet"
echo
echo "    # dnf/zypper:"
echo "    sudo curl -o /etc/yum.repos.d/marionnet.repo $URL/rpm/marionnet.repo   # if published"
echo "    sudo dnf install marionnet"
test -n "$SIGN_KEY" || info "Release is unsigned, hence [trusted=yes] (see --sign, and the header)"
