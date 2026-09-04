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

# Turn a frozen binary policy into what a guest is told to do.
# Stage 3a of the work-stream `triage-binaires-image-invitee' (docs/triage-binaires-image-invitee.md,
# § 5): a probe OBSERVES (filesystem.probe-image-binaries.sh), an agent DECIDES once -- and what it
# decided lives in uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.<tag>.tsv -- and this
# script APPLIES, mechanically, without judging anything.
#
#   Makefile.d/filesystem.apply-binary-policy.sh --image machine-debian-trixie-16341 --dry-run
#
# --- IT DECIDES NOTHING, AND IT INVENTS NOTHING ---
#
# Every command it runs comes from the `action' column of a line of the policy, verbatim. It adds
# no command of its own, it rewrites none, and it REFUSES the whole file -- naming the line -- as
# soon as a line does not say plainly what to do: an unknown verdict, a `drop' or a `fix' without
# an action, an action written on a line whose verdict wants none. Skipping such a line with a
# warning would leave an action silently unplayed, which is the very family of defect this
# work-stream has already paid for twice (episodes 3 and 4). Refusing to name rather than
# inventing a name is the same rule as `artefact_name' (episode 30b ter of
# `modernisation-installation-marionnet').
#
# --- MEASURE BEFORE PRODUCING ---
#
# `--measure' relays `--no-export' to filesystem.update-published-image.sh: the commands are
# played in the guest, and NOTHING is exported -- no variant, no image, nothing in the release
# directory. That option exists because of episode 4, where the guest refuted the action the
# policy carried: `apt-get -y purge qtchooser' would have removed qtbase5-dev-tools too, hence
# seven wrappers that WORK, to repair thirty-two that do not. An action of a policy is measured
# in the guest before it is applied.
#
# `--dry-run' goes one step further back: it prints the command line that would be run and boots
# nothing at all. It is how the translation itself gets read before anything costs a boot.
#
# --- WHAT `--only-verdict' IS FOR ---
#
# The policy holds every verdict of a distribution, but an episode applies one family at a time
# and re-probes in between. `--only-verdict drop' plays the removals and leaves the `fix' lines
# -- whose package names are candidates the re-probe has yet to confirm -- alone.

set -o pipefail

function info { echo "$0: $*" >&2; }
function warn { echo "$0: warning: $*" >&2; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
 cat 1>&2 <<EOF
Usage: $0 --image NAME [OPTIONS]

  --image NAME         the published image to act on, e.g. machine-debian-trixie-16341
  --policy FILE        the policy to apply
                       (default: uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.<tag>.tsv,
                        <tag> being read from the image name -- machine-debian-TRIXIE-16341)
  --only-verdict LIST  the verdicts to play, comma separated (default: drop,fix)
  --in-guest CMD       an extra command, played AFTER the ones the policy gives; repeatable.
                       The way a measurement run checks what the policy was not supposed to
                       touch (episode 4: the seven wrappers which still work).
  --dry-run            print the command line which would be run, boot nothing
  --measure            play the commands in the guest and export NOTHING (--no-export)
  --from DIR           where the image and its .conf live
  --kernel PATH        the UML kernel to make visible to Marionnet
  --variant NAME       name of the exported variant
  --memory N           MiB given to the machine
  --binary PATH        the marionnet to drive
  --output-dir DIR     relayed to the publisher
  --no-publish         make the variant, publish nothing
  --keep-project       do not remove the temporary project directory
  -y, --yes            do not ask before booting
  -h, --help           this help

Without --dry-run and without --measure, this WRITES A NEW IMAGE in the release directory
(nothing is uploaded). The exit status is 0 if the policy was applied, 2 if it could not be.
EOF
}

# --- Options.
IMAGE=""; POLICY=""; ONLY_VERDICT="drop,fix"; DRY_RUN=0; MEASURE=0
declare -a EXTRA_IN_GUEST=()
declare -a RELAY=()

while (($#)); do
  case "$1" in
    --image)          IMAGE=${2:-};            shift 2 ;;
    --policy)         POLICY=${2:-};           shift 2 ;;
    --only-verdict)   ONLY_VERDICT=${2:-};     shift 2 ;;
    --in-guest)       EXTRA_IN_GUEST+=("${2:-}"); shift 2 ;;
    --dry-run)        DRY_RUN=1;               shift ;;
    --measure)        MEASURE=1;               shift ;;
    # Relayed verbatim to filesystem.update-published-image.sh: this script does not
    # re-document its brother's options, it hands them over.
    --from|--kernel|--variant|--memory|--binary|--output-dir)
                      RELAY+=("$1" "${2:-}");  shift 2 ;;
    --no-publish|--keep-project|-y|--yes)
                      RELAY+=("$1");           shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage; die "unexpected argument '$1'" ;;
  esac
done

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
RESPIN="$HERE/filesystem.update-published-image.sh"
PUBLISHER="$HERE/filesystem.prepare-snapshot-to-publish.sh"

test -n "$IMAGE" || { usage; die "--image is required"; }
test -x "$RESPIN" || die "no executable at $RESPIN"

case "$IMAGE" in
  machine-*) : ;;
  router-*)  die "$IMAGE is a ROUTER image: on the published side it is a symbolic LINK to a
machine image, which carries the binaries. Act on the machine image it points to." ;;
  *)         die "$IMAGE is not an image name (it should begin with \`machine-')" ;;
esac

# --- The policy.
#
# Its name is DERIVED from the image name, and the derivation refuses rather than guesses: the
# policy is per distribution (§ 6 of the doc), and applying trixie's judgements to a wheezy image
# would remove names nobody ever probed there.
if test -z "$POLICY"; then
  # machine-debian-trixie-16341 -> debian-trixie-16341 -> trixie
  TAG=$(cut -d- -f2 <<<"${IMAGE#machine-}")
  test -n "$TAG" || die "cannot read a distribution tag out of the image name \`$IMAGE': give --policy"
  POLICY="$ROOT/uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.$TAG.tsv"
  test -r "$POLICY" || die "no policy for \`$TAG' at $POLICY
An image whose distribution has no policy has not been triaged: probe it first
(Makefile.d/filesystem.probe-image-binaries.sh --image $IMAGE), decide, then come back."
fi
test -r "$POLICY" || die "--policy: cannot read $POLICY"

# --- The verdicts this run plays.
KNOWN_VERDICTS="keep fix drop ignore"
declare -A PLAYED=()
while read -r v; do
  test -n "$v" || continue
  grep -qw -- "$v" <<<"$KNOWN_VERDICTS" \
    || die "--only-verdict: \`$v' is not a verdict of the policy format (one of: $KNOWN_VERDICTS)"
  PLAYED[$v]=1
done < <(tr ',' '\n' <<<"$ONLY_VERDICT")
test "${#PLAYED[@]}" -gt 0 || die "--only-verdict: nothing to play"

# --- Reading the policy: four tab separated columns, exceptions only.
#
# Everything which is not a comment or a blank line MUST parse. A line which does not is not a
# line to skip: it is a judgement whose meaning is unclear, and the file is refused as a whole.
declare -a ACTIONS=() ACTED_NAMES=()
declare -a SEEN_NAMES=()
declare -A COUNT=()
LINE_NO=0
while IFS= read -r line; do
  LINE_NO=$((LINE_NO + 1))
  case "$line" in ''|'#'*) continue ;; esac
  # The count of fields is checked before anything is read out of them.
  field_no=$(awk -F'\t' '{print NF}' <<<"$line")
  test "$field_no" = 4 \
    || die "$POLICY:$LINE_NO: $field_no tab separated field(s), 4 expected (name verdict action reason):
  $line"
  name=$(cut -f1 <<<"$line")
  verdict=$(cut -f2 <<<"$line")
  action=$(cut -f3 <<<"$line")
  reason=$(cut -f4 <<<"$line")
  test -n "$name"    || die "$POLICY:$LINE_NO: empty name"
  test -n "$reason"  || die "$POLICY:$LINE_NO: empty reason -- a verdict nobody can contest is a verdict nobody can check"
  case " $KNOWN_VERDICTS " in
    *" $verdict "*) : ;;
    *) die "$POLICY:$LINE_NO: unknown verdict \`$verdict' for \`$name' (one of: $KNOWN_VERDICTS)" ;;
  esac
  # An action is required by, and only by, the verdicts which act.
  case "$verdict" in
    drop|fix)
      test -n "$action" && test "$action" != "-" \
        || die "$POLICY:$LINE_NO: verdict \`$verdict' for \`$name' without an action to play" ;;
    keep|ignore)
      test -z "$action" || test "$action" = "-" \
        || die "$POLICY:$LINE_NO: verdict \`$verdict' for \`$name' carries an action (\`$action'):
a line which does nothing must say so with \`-', or its verdict is wrong" ;;
  esac
  SEEN_NAMES+=("$name")
  COUNT[$verdict]=$(( ${COUNT[$verdict]:-0} + 1 ))
  if test -n "${PLAYED[$verdict]:-}"; then
    ACTIONS+=("$action")
    ACTED_NAMES+=("$name")
  fi
done < "$POLICY"

test "${#SEEN_NAMES[@]}" -gt 0 || die "$POLICY: no policy line at all"
info "policy     : $POLICY"
info "verdicts   : $(for v in $KNOWN_VERDICTS; do test -n "${COUNT[$v]:-}" && printf '%s %s  ' "${COUNT[$v]}" "$v"; done)"
info "playing    : ${#ACTIONS[@]} action(s) for verdict(s) $ONLY_VERDICT$( ((${#EXTRA_IN_GUEST[@]})) && echo ", plus ${#EXTRA_IN_GUEST[@]} of your own" )"
test "${#ACTIONS[@]}" -gt 0 || die "nothing to play: no line of the policy carries a verdict among $ONLY_VERDICT"

# --- Do the acted names still exist in this image? A measurement, not a gate.
#
# The publisher rebuilds BINARY_LIST by reading the image it produces
# (filesystem.prepare-snapshot-to-publish.sh, `binary_list_of_image'), so a name which has
# ALREADY been dropped is simply not there any more. That is the expected shape of a second run,
# not an error -- and it is precisely the proof a re-probe looks for. So we say what we see and
# go on, rather than refusing.
FROM_DIR=""
for ((i = 0; i < ${#RELAY[@]}; i++)); do
  test "${RELAY[$i]}" = "--from" && FROM_DIR=${RELAY[$((i + 1))]}
done
if test -z "$FROM_DIR"; then
  SERIES=$("$PUBLISHER" --print-series 2>/dev/null) || SERIES=""
  test -z "$SERIES" || FROM_DIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
fi
if test -n "$FROM_DIR" && test -r "$FROM_DIR/$IMAGE.conf"; then
  CANDIDATES=$(sed -n "s/^BINARY_LIST='\(.*\)'.*/\1/p" "$FROM_DIR/$IMAGE.conf" | head -n 1 | tr ' ' '\n' | grep -v '^$' || true)
  if test -n "$CANDIDATES"; then
    absent=$(comm -23 <(printf '%s\n' "${ACTED_NAMES[@]}" | sort -u) <(sort -u <<<"$CANDIDATES") | tr '\n' ' ')
    if test -n "${absent// /}"; then
      info "note       : $(wc -w <<<"$absent") of the acted names are NOT in the BINARY_LIST of this
             image -- already applied, or a name this image never carried: ${absent% }"
    else
      info "names      : all ${#ACTED_NAMES[@]} acted names are in the BINARY_LIST of $IMAGE"
    fi
  fi
else
  warn "no $IMAGE.conf found: the acted names could not be checked against BINARY_LIST"
fi

# --- The command line.
declare -a CMD=("$RESPIN" --image "$IMAGE")
CMD+=("${RELAY[@]}")
((MEASURE == 0)) || CMD+=(--no-export)
for a in "${ACTIONS[@]}";        do CMD+=(--in-guest "$a"); done
for a in "${EXTRA_IN_GUEST[@]}"; do CMD+=(--in-guest "$a"); done

if ((DRY_RUN)); then
  info "--dry-run: nothing is booted, this is the command line"
  printf '%q ' "${CMD[@]}"; echo
  exit 0
fi

((MEASURE == 0)) || info "--measure: the commands will be played in the guest, NOTHING will be exported"
exec "${CMD[@]}"
