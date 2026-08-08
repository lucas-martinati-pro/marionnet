# Guest side of example 2 — this is NOT run on the host.
#
# Marionnet drops this content in the machine's hostfs and the guest relay sources it at the
# end of the boot, as bash. Two things matter to a script driving the session:
#
#   - /mnt/hostfs is a real *host* directory, so whatever is written there is readable by the
#     script that started the machine, without any network;
#   - the last block is the "guest is ready" signal that `mrnctl wait <n> --ready' waits for.
#     Marionnet never writes it and never erases it: the guest is the only one that knows.
#
# Install it with:  mrnctl rc-set <machine> --from=<absolute path of this file> --enable

# ---- the machine's part of the lab -------------------------------------------------------

ip addr add 10.0.0.1/24 dev eth0 2>/dev/null
ip link set eth0 up

# Whatever the exercise is about. Its output goes back to the host through /mnt/hostfs.
{
  echo "=== $(date) — $(hostname) ==="
  ip -brief addr show eth0
  ping -c 3 -W 2 10.0.0.2 || echo "peer unreachable"
} > /mnt/hostfs/lab.log 2>&1

# ---- the "ready" signal, written last and written atomically ------------------------------

# The line is free: a verdict, a version, a step number. It comes back in the answer of
# `wait --ready', so the guest can report a result and not merely its presence.
LINE="ready"

# Atomic on purpose: the host probe may otherwise read a truncated line. The fallback covers
# the case where rename(2) is not available on that mount.
printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
  mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
  printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready

# Do NOT rename this marker into anything matching /mnt/hostfs/…relay* : the guest relay
# sources that glob at the end of the boot, so such a file would be *executed* as bash.
