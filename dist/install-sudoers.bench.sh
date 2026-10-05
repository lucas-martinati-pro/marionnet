#!/usr/bin/env bash
# GPL-2.0-or-later. Exercise the complete .deb installer with isolated fixtures.
# No network, package manager, sudo or real /etc writes: all external effects are
# substituted. The sudo stub NEVER executes its argument and rejects unexpected calls.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${1:-$SCRIPT_DIR/install.sh}"
for tool in bash tar sha256sum awk; do
  command -v "$tool" >/dev/null || { echo "SKIP: $tool is required"; exit 77; }
done
bench_root="$(mktemp -d /tmp/marionnet-install-sudoers.XXXXXX)"
trap 'rm -rf -- "$bench_root"' EXIT
mkdir -p "$bench_root/bin" "$bench_root/payload/usr/bin"
printf 'fixture binary\n' > "$bench_root/payload/usr/bin/marionnet.native"
tar -cf "$bench_root/layer.tar" -C "$bench_root/payload" ./usr/bin/marionnet.native
printf 'fixture package\n' > "$bench_root/package.deb"

cat > "$bench_root/bin/curl" <<'STUB'
#!/bin/bash
set -euo pipefail
target="" url=""
while (( $# > 0 )); do
  case "$1" in
    -o) target="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -n "$target" ]] || exit 90
case "$url" in
  */SHA256SUMS)
    hash="$(sha256sum "$INSTALL_BENCH_ROOT/package.deb")"
    printf '%s  marionnet-all-in-one_9.9.9_amd64.deb\n' "${hash%% *}" > "$target"
    ;;
  */marionnet-all-in-one_9.9.9_amd64.deb) cp "$INSTALL_BENCH_ROOT/package.deb" "$target" ;;
  *) echo "FAIL: unexpected HTTP request: $url" >&2; exit 90 ;;
esac
STUB

cat > "$bench_root/bin/sudo" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s\t' "$@" >> "$INSTALL_BENCH_CASE/calls"
printf '\n' >> "$INSTALL_BENCH_CASE/calls"
case "$1" in
  dpkg|apt|rm) exit 0 ;; # Deliberately do not delegate, even for rm.
  marionnet-sudoers.sh)
    case "${2:-}" in
      install)
        case "$INSTALL_BENCH_MODE" in
          install-refused) echo 'sudoers: generated rule REJECTED by visudo' >&2; exit 2 ;;
          helper-missing) echo 'sudo: marionnet-sudoers.sh: command not found' >&2; exit 127 ;;
          *) exit 0 ;;
        esac
        ;;
      check)
        if [[ "$INSTALL_BENCH_MODE" = check-refused ]]; then
          echo 'sudoers: LAST matching rule wins; sudo REFUSES it' >&2
          exit 5
        fi
        exit 0
        ;;
      *) exit 90 ;;
    esac
    ;;
  tee)
    # Simulate the old fallback ONLY in our private fixture: never touch /etc.
    cat > "$INSTALL_BENCH_CASE/sudoers"
    exit 0
    ;;
  chmod) exit 0 ;;
  *) echo "FAIL: unexpected privileged command: $*" >&2; exit 90 ;;
esac
STUB

cat > "$bench_root/bin/dpkg-deb" <<'STUB'
#!/bin/bash
case "$1" in
  --fsys-tarfile) cat "$INSTALL_BENCH_ROOT/layer.tar" ;;
  -f) echo 'libc6:i386' ;;
  *) exit 90 ;;
esac
STUB
printf '#!/bin/bash\nexit 1\n' > "$bench_root/bin/dpkg"
printf '#!/bin/bash\necho x86_64\n' > "$bench_root/bin/uname"
printf '#!/bin/bash\necho "Marionnet version 9.9.9"\n' > "$bench_root/bin/marionnet"
cat > "$bench_root/bin/marionnet.native" <<'STUB'
#!/bin/bash
[[ "$1" = --paths ]] || exit 90
printf 'kernels : %s/kernels\n' "$INSTALL_BENCH_CASE"
STUB
printf '#!/bin/bash\necho "all libraries found"\n' > "$bench_root/bin/ldd"
chmod +x "$bench_root/bin/"*
# The simulated apt transaction installs the i386 interpreter. Do not require it
# on the machine running a test which is expressly forbidden to install packages.
# Only this literal existence test is substituted; all other [ tests are real.
cat > "$bench_root/platform.sh" <<'STUB'
function [ {
  if [[ $# = 3 && "$1" = -e && "$2" = /lib/ld-linux.so.2 && "$3" = ']' ]]; then
    return 0
  fi
  builtin [ "$@"
}
STUB

failures=0
check() {
  if [[ "$1" = true ]]; then echo "PASS: $2"
  else echo "FAIL: $2"; failures=$((failures + 1)); fi
}
has_line() { grep -F -- "$2" "$1" >/dev/null; }

run_case() {
  local mode="$1" case_dir="$bench_root/$1" rc=0 result=false
  mkdir -p "$case_dir/dist" "$case_dir/kernels"
  cp "$INSTALLER" "$case_dir/dist/install.sh"
  printf '#!/bin/bash\nexit 0\n' > "$case_dir/kernels/linux-6.12.95-i386"
  chmod +x "$case_dir/kernels/linux-6.12.95-i386"
  # Existing permissions must survive a failed install. The old fallback overwrites
  # this fixture with its broad grant, mirroring what it used to do in /etc.
  printf '# existing scoped grant\n' > "$case_dir/sudoers"
  cp "$case_dir/sudoers" "$case_dir/sudoers.before"
  PATH="$bench_root/bin:$PATH" USER=student SUDO_USER=student BASH_ENV="$bench_root/platform.sh" \
    INSTALL_BENCH_ROOT="$bench_root" INSTALL_BENCH_CASE="$case_dir" INSTALL_BENCH_MODE="$mode" \
    MARIONNET_REPO=fixture/fixture MARIONNET_VERSION=9.9.9 \
    bash "$case_dir/dist/install.sh" --release --no-wheezy 9.9.9 \
    > "$case_dir/stdout" 2> "$case_dir/stderr" || rc=$?

  [[ -f "$case_dir/calls" ]] || { echo "FAIL: $mode never reached privileged configuration"; exit 1; }
  if has_line "$case_dir/calls" $'marionnet-sudoers.sh\tinstall\tstudent\t'; then result=true; fi
  check "$result" "$mode: the canonical installer is called with the target account"
  result=false
  if cmp -s "$case_dir/sudoers.before" "$case_dir/sudoers"; then result=true; fi
  check "$result" "$mode: no fallback rewrites the existing grant"
  result=false
  if ! has_line "$case_dir/calls" $'tee\t/etc/sudoers.d/' &&
     ! has_line "$case_dir/calls" $'chmod\t0440\t/etc/sudoers.d/'; then result=true; fi
  check "$result" "$mode: no alternative sudoers write is attempted"

  result=false
  if [[ "$mode" = success ]]; then
    [[ "$rc" = 0 ]] && result=true
    check "$result" "success: installation finishes"
    result=false
    if has_line "$case_dir/calls" $'marionnet-sudoers.sh\tcheck\tstudent\t'; then result=true; fi
    check "$result" "success: effective permissions are checked after configuration"
    result=false
    if has_line "$case_dir/stdout" 'installé et prêt à l’emploi' ||
       has_line "$case_dir/stdout" "installé et prêt à l'emploi"; then result=true; fi
    check "$result" "success: the final success message remains reachable"
  else
    [[ "$rc" != 0 ]] && result=true
    check "$result" "$mode: installation exits nonzero"
    result=false
    if ! has_line "$case_dir/stdout" "installé et prêt à l'emploi"; then result=true; fi
    check "$result" "$mode: no false success is announced"
    result=false
    case "$mode" in
      install-refused) has_line "$case_dir/stderr" 'REJECTED by visudo' && result=true ;;
      helper-missing) has_line "$case_dir/stderr" 'command not found' && result=true ;;
      check-refused) has_line "$case_dir/stderr" 'LAST matching rule wins' && result=true ;;
    esac
    check "$result" "$mode: the original diagnostic remains visible"
    result=false
    if [[ "$mode" = check-refused ]]; then
      has_line "$case_dir/calls" $'marionnet-sudoers.sh\tcheck\tstudent\t' && result=true
    else
      ! has_line "$case_dir/calls" $'marionnet-sudoers.sh\tcheck\tstudent\t' && result=true
    fi
    check "$result" "$mode: validation runs only after successful configuration"
  fi
}

for mode in success install-refused helper-missing check-refused; do run_case "$mode"; done
echo "$failures failure(s)"
(( failures == 0 ))
