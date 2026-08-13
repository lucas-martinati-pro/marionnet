# Guest side — the SOLUTION of the lab, as a boot scenario for r1. NOT run on the host, and NOT
# part of what is handed out: build.sh leaves r1 unconfigured, play.sh installs this file to
# check that the lab is playable and that the key passes on a correct copy.
#
# Two deliberate choices, both of them measured:
#
#   · `sysctl -w' rather than `echo 1 > /proc/sys/…': the journal of this scenario is a `set -x'
#     trace, and a trace does NOT show redirections — `echo 1 > …/ip_forward' leaves the words
#     `echo 1' and nothing else. A correct machine would then fail an assertion about its own
#     configuration. What proves the state is the report (`report r1'), not the trace;
#   · no `|| true' anywhere: a failure absorbed on the left of `||' never reaches the journal,
#     and `journal r1 rc_config ok' would pass on a scenario that did nothing.

# 1. routing
sysctl -w net.ipv4.ip_forward=1

# 2. filtering: nothing crosses this router unless it was asked for from the LAN
iptables -P FORWARD DROP
iptables -A FORWARD -i eth0 -o eth2 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 3. source NAT: the LAN goes out with the router's outside address
iptables -t nat -A POSTROUTING -o eth2 -j MASQUERADE

LINE="ready"
printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
  mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
  printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready
