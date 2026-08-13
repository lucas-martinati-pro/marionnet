# Guest side — sourced by the relay at the end of m1's boot. NOT run on the host.
#
# Installed with:  mrnctl rc-set m1 --from=<absolute path of this file> --enable
#
# m1's address is declared in the lab, so it is already on eth0 here. What a declaration cannot
# carry is the rest: the default route, and the "I am ready" signal the host waits for.

ip route replace default via 192.168.1.254

# The ready marker, written last and written atomically: the host probe may otherwise read a
# truncated line. `wait m1 --ready' waits for this file and for nothing else — Marionnet never
# writes it.
LINE="ready"
printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
  mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
  printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready
