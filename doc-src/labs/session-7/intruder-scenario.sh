# Guest side — sourced by the relay at the end of intruder's boot. NOT run on the host.
#
# The outsider. Its address is declared in the lab; it needs a route back towards the LAN only
# to make the *absence* of an answer meaningful — with no route at all, a failed ping would
# prove nothing about the student's firewall.

ip route replace default via 10.0.0.254

LINE="ready"
printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
  mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
  printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready
