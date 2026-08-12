# Driving Marionnet from a script

*User guide to Marionnet's control channel — for the teacher who wants a lab built, started and
checked without clicking, and for the agent that drives Marionnet to test something.*

Marionnet can be driven from the outside while its window stays on screen, alive and
observable. You start it with one extra option, and from then on a shell script — or anything
that can write a line to a unix socket — can do what a hand does with the mouse: create
machines, cable them, give them addresses, start them, wait, read results, save the project.

This guide teaches the **shape** of that channel and a handful of complete recipes. It
deliberately does **not** list the commands: the running Marionnet publishes its own
vocabulary (see [§ 4](#4-the-command-list-is-not-in-this-guide)).

* Design and rationale (in French, for developers): `docs/pilotage-par-script.md`.
* The client script: `useful-scripts/marionnet-ctl`, also reachable as `mrnctl`.

---

## 1. Starting a driven session

```bash
marionnet --control-socket /tmp/marionnet.sock
```

That is the whole setup. The option does three things:

1. it creates the unix socket `/tmp/marionnet.sock` and serves one line-oriented session per
   client on it (up to 8 at a time);
2. it switches Marionnet to **script mode**: the windows Marionnet opens *by itself* — the
   splash screen, the summary of the adaptations made to an old project, a load error — are
   captured and closed instead of waiting for a human who is not there (see
   [§ 12](#12-the-windows-that-open-by-themselves));
3. it changes nothing else. The GUI is the same GUI, and a human can keep using it while a
   script drives it.

Without the option no socket exists, so a Marionnet started normally cannot be driven — there
is nothing to connect to.

Two options worth knowing right away:

| Option | What it does |
|---|---|
| `--control-socket PATH` | serve the channel on `PATH` (and enter script mode) |
| `-r`, `--run` | immediately run the project given on the command line |

`-r` is what makes a saved lab a *deliverable*: `marionnet --control-socket … -r lab.mar`
opens the project **and starts everything in it** before your script says a word.

### The client

Requests are plain lines, so `socat`, `nc` or a here-doc would do. In practice you use the
client shipped with Marionnet:

```bash
export MARIONNET_CONTROL_SOCKET=/tmp/marionnet.sock

mrnctl status
mrnctl add machine m1 --ports=2
mrnctl start m1
```

The socket is resolved from `--socket=PATH`, else from `$MARIONNET_CONTROL_SOCKET`, and
nowhere else: the client never goes looking for a running Marionnet. If neither is set it
says so and stops.

`mrnctl` needs `socat`. It needs `jq` only for its two formatting options, `--pretty` and
`--query`.

### Tab completion

```bash
. /path/to/marionnet-completion.bash      # or drop it in /etc/bash_completion.d/
```

From then on, TAB completes verbs, options, and — this is the part worth having — the **real
names of the session**:

```
$ mrnctl connect c2 <TAB>
m1:  m2:  s1:
$ mrnctl connect c2 s1:<TAB>
s1:port1  s1:port2  s1:port3  s1:port4  s1:port5  s1:port6  s1:port7  s1:port8
$ mrnctl ifconfig-set m1 eth0 <TAB>
mac-address  mtu  ipv4-address  ipv4-gateway  ipv6-address  ipv6-gateway
```

Components, ports, disk states and field names come from the Marionnet you are driving, so they
are the ones that exist, not a list someone typed. The verbs and options come from `help`, so a
verb added to Marionnet completes the day it exists.

With no Marionnet running there is nothing to publish. Point the completion at a snapshot and
verbs and options still work — the *names*, of course, cannot:

```bash
mrnctl help > ~/.marionnet-grammar.json
export MARIONNET_CTL_GRAMMAR=~/.marionnet-grammar.json
```

It needs `jq`. Without it, or without anything to read, it stays silent rather than guessing.

---

## 2. Five minutes, end to end

```bash
export MARIONNET_CONTROL_SOCKET=/tmp/marionnet.sock

marionnet --control-socket "$MARIONNET_CONTROL_SOCKET" &
sleep 5                                    # let the GUI come up

mrnctl new /tmp/demo.mar                   # a project must exist before anything else
mrnctl add machine m1
mrnctl add machine m2
mrnctl add switch   s1 --ports=4
mrnctl connect c1 m1:eth0 s1:port1
mrnctl connect c2 m2:eth0 s1:port2

mrnctl ifconfig-set m1 eth0 ipv4-address 10.0.0.1/24
mrnctl ifconfig-set m2 eth0 ipv4-address 10.0.0.2/24

mrnctl start m1
mrnctl start m2
mrnctl wait m1 --state=on --timeout=120
mrnctl wait m2 --state=on --timeout=120

mrnctl -q '.nodes[] | "\(.name) \(.state)"' ls
mrnctl save-as /tmp/demo.mar
mrnctl quit
```

Every one of those lines is a request; every one gets a JSON line back. The rest of this
guide is about what those answers mean and where the traps are.

---

## 3. The shape of the channel

**One request per line, one JSON object per line back.** A request is a verb, then positional
arguments, then options:

```
<verb> [<argument>…] [--option=<value>…]
```

Component names are identifiers — no spaces — which is why arguments can be split on spaces
without ambiguity. Where a command takes free text (a comment, a one-line startup script), the
surplus belongs to the **last** argument; everywhere else a surplus argument is refused, with
the syntax printed in clear.

### Answers

Success carries `"ok": true` and the fields the command has to report:

```json
{"ok":true,"count":3,"nodes":[{"name":"m1","kind":"machine","state":"off"}, …]}
```

A refusal carries `"ok": false`, a stable machine-readable `error` code, and a `detail`
written for a human:

```json
{"ok":false,"error":"forbidden_transition","detail":"\"m1\" cannot start from state \"on\""}
```

The codes you can branch on:

| Code | Meaning |
|---|---|
| `unknown_command` | no such verb (the answer lists the ones that exist) |
| `bad_argument` | wrong arity, wrong option, malformed value |
| `no_active_project` | nothing is open; open or create a project first |
| `unknown_node`, `unknown_port`, `unknown_field`, `unknown_direction`, `unknown_target`, `unknown_state`, `unknown_can` | the thing named does not exist |
| `forbidden_transition` | the state machine forbids it *right now* (see [§ 5](#5-a-script-may-do-what-the-gui-may-do)) |
| `constraint_violated` | the value is refused by the same check the GUI applies |
| `restart_choice_required` | the change needs a running node restarted, and you did not say whether to |
| `unsaved_changes` | the project has changes and you did not say `--save` or `--no-save` |
| `timeout` | the deadline expired (the answer says what was last observed) |
| `internal` | a bug on our side; the detail carries what was captured |

### Exit codes

`mrnctl` maps the answer onto four exit codes, so that `mrnctl … && …` can be trusted:

| Code | Meaning |
|---|---|
| `0` | the channel accepted |
| `1` | the channel answered, and it refused (`ok:false`) |
| `2` | our own fault: no socket, missing tool, unknown client option |
| `3` | nothing came back, or what came back is not a channel reply |

The distinction between `1` and `3` is the one that matters in a script: `1` is an answer you
can read, `3` means Marionnet is gone, frozen, or was never there.

### Reading the answer

By default `mrnctl` prints the raw JSON line — one line, greppable, pipeable. Two options
change that, and both need `jq`:

```bash
mrnctl --pretty status                       # indented
mrnctl -q '.nodes[].name' ls                 # a jq filter applied to the answer
mrnctl -q '.ok' start m1
```

---

## 4. The command list is not in this guide

Ask the running Marionnet:

```bash
mrnctl help                # every command, with its syntax and its arity
mrnctl help connect        # the syntax of one of them
```

This is not a stylistic choice. Since the client knows no grammar, the **server is the single
source of truth** for the vocabulary: a verb added to Marionnet is usable and documented the
moment it exists, and no second list can drift away from it. A command table copied into this
guide would be exactly such a second list — right on the day it was written, wrong afterwards.

So this guide names commands in recipes, and tells you what their answers mean, but for
*"what exists and how many arguments does it take"*, `help` is the authority.

---

## 5. A script may do what the GUI may do

This is the contract, and it is worth stating plainly: **the channel is not a back door.** A
script has the same possibilities and the same limits as a hand on the mouse. A component that
cannot be deleted while it runs cannot be deleted by the channel either; a machine that is
already on cannot be started twice.

Refusals of this kind come back as `forbidden_transition`. You do not have to provoke them to
find out — ask first:

```bash
mrnctl can m1                        # the actions allowed on m1 right now
mrnctl can                           # the same, for every component and every cable
mrnctl ls --can=del                  # every node that can be deleted right now
```

The answer of `can` lists what is allowed, so a test is a membership test:

```json
{"ok":true,"name":"m1","kind":"machine","state":"off",
 "can":["set","del","start"],"beyond_gui":[]}
```

The eight action names are the command names — `set`, `del`, `start`, `stop`, `suspend`,
`resume`, `poweroff`, `restart` — so nothing has to be translated between asking and doing.

```bash
mrnctl -q '.can | index("del") != null' can m1     # true / false
```

The rule of thumb: **test `can` before acting**, and treat `forbidden_transition` as a bug in
your script rather than an accident.

Three things to keep in mind:

* **Cables are the exception, on purpose.** A cable can be edited and removed *while the
  network runs* — because you can do that with real hardware: you unplug it and plug it
  somewhere else without switching anything off. `can` reports this faithfully.
* **A few commands go beyond what the GUI offers**, and say so. Per-component `poweroff` and
  `restart` have no button in the interface; they are guarded exactly like the others and
  marked `beyond_gui` in the answer of `can`.
* **The model refuses a bad name before writing anything.** A name that is not an identifier,
  or that is already taken, is refused by `add`, `rename` and `set … name` alike — no
  half-applied change.

---

## 6. `accepted` is not `done`

Starting a machine boots a real Linux kernel. The channel does not lie about that: a
transition command answers **`accepted`**, meaning *the request was legal and has been
handed over*, never *it is finished*.

```json
{"ok":true,"component":"m1","action":"start","accepted":true,"beyond_gui":false}
```

Waiting is a separate, explicit step, and there are two very different things to wait for.

### `--state` — the process is running

```bash
mrnctl wait m1 --state=on --timeout=120
mrnctl wait-all --state=off --timeout=180
```

`on` means *the UML process is running*. It does **not** mean the guest has finished booting.
On a Debian guest the gap is real and measurable: `--state=on` comes back in under a second,
where the guest only becomes usable some five seconds later.

On expiry you get `error:"timeout"` with the state actually observed last, and `wait-all` adds
a `pending` field naming the laggards — enough to diagnose without a second round trip.

### `--ready` — the guest says it is ready

Marionnet cannot know when a guest is ready; only the guest knows. So the guest tells you, by
writing one file:

```bash
mrnctl wait m1 --ready --timeout=300
# {"ok":true,"ready":true,"line":"ready","marker":"…/marionnet-guest-ready","mtime":…}
```

The convention is one line long: **the startup scenario writes
`/mnt/hostfs/marionnet-guest-ready`**, and `wait --ready` watches the host side of that
directory. Marionnet never creates it, never deletes it, and never touches the guest.

Three properties make it safe, and each one is a trap avoided:

* **Write it atomically.** The probe may otherwise read a truncated line:

  ```bash
  LINE='ready'          # any single line: a verdict, a version, a step number…
  printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
    mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
    printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready
  ```

* **A marker left by the previous run is ignored**, by date: it is compared against
  `boot_parameters`, which Marionnet rewrites at every device construction. You have nothing
  to clean up between runs, and `start` gains no side effect.

* **Do not rename it.** The guest relay sources every `/mnt/hostfs/…relay*` file at the end of
  boot: a marker whose name fell into that glob would be *executed* as bash.

The first line of the marker comes back in the answer (`line`), so the guest can report a
verdict, not merely its presence. `wait-all --ready` does not exist: machines boot in
parallel, so waiting for them one after another costs the same total time.

---

## 7. Recipe A — build a lab, save it, replay it

A project must exist before any component does; `add` on nothing answers `no_active_project`.

```bash
mrnctl new /tmp/lab.mar                    # or: mrnctl open /tmp/existing.mar
mrnctl add machine m1 --ports=2
mrnctl add machine m2
mrnctl add switch   s1 --ports=8
mrnctl connect c1 m1:eth0 s1:port1
mrnctl connect c2 m2:eth0 s1:port2
mrnctl save-as /tmp/lab.mar
```

Notes that save time:

* **Ports are named, not indexed** — `m1:eth0`, `s1:port3`, exactly as the GUI and the `.mar`
  file name them. Mind the two conventions, which are the GUI's: a machine numbers its
  interfaces **from 0** (`eth0`, `eth1`), a switch or a hub numbers its ports **from 1**
  (`port1`, `port2`). A refusal lists the free port names of the node, so there is nothing to
  guess.
* **A crossover cable** is `connect c3 m1:eth0 m2:eth0 --crossover`.
* **`add machine` picks a bootable pair by itself**: it takes the first kernel the chosen
  filesystem declares, like the dialog does. A machine added by the channel starts.
* **A cable is not renamed** — neither by the GUI nor by the channel. Delete it and connect a
  new one.
* **`new`, `close` and `open` refuse to throw away work**: if the current project has changes
  they answer `unsaved_changes` until you say `--save` or `--no-save`. That is deliberate —
  the script must state its intent, not inherit a default.

There is no file format to generate. **Marionnet is the only legitimate producer of a `.mar`**
(it is a binary image, not XML): a lab is built through the channel and written by `save-as`.
Replaying it is then a command line:

```bash
marionnet --control-socket /tmp/marionnet.sock -r /tmp/lab.mar
```

---

## 8. Recipe B — addresses and defects

The four tables of the GUI (*ifconfig*, *defects*, *history*, *documents*) are readable and,
for the first three, writable. Reading serves the tree as a tree:

```bash
mrnctl ifconfig            # every addressable component
mrnctl ifconfig m1         # one of them
mrnctl defects             # every component, plus the cables
```

A table is served **as a tree**, because that is what it is in the GUI (a node, its ports,
their directions). `columns` gives the headers in the order the interface shows them, and every
row is `{"fields": …, "children": […]}`:

```json
{"ok":true,"treeview":"ifconfig",
 "columns":["Name","Type","MAC address","MTU","IPv4 address", …],
 "slugs":["mac-address","mtu","ipv4-address","ipv4-gateway","ipv6-address","ipv6-gateway"],
 "count":1,"rows":[{"fields":{"Name":"m1","Type":"machine"},
                    "children":[{"fields":{"Name":"eth0","MTU":"1500", …},"children":[]}]}]}
```

A column a row does not carry is **omitted**, not served as `null` — a device row has no MTU,
and an absent field is not an empty one. The populations differ too, and on purpose:
`ifconfig` only receives the components that have addresses, where `defects` receives
everything, cables included.

Writing is **one field at a time**, and the field is named by the **slug** of its column:
lowercase, every run of non-alphanumeric characters becomes one dash, trailing dashes dropped.
So `IPv4 address` is written `ipv4-address`, `Loss %` is `loss`, `Minimum delay (ms)` is
`minimum-delay-ms`.

You never have to apply that rule yourself: every read answer carries a `slugs` field beside
`columns`, holding exactly the names that table accepts for writing — which is fewer than the
columns it shows, `Name` and `Type` being readable and not writable.

```bash
mrnctl -q '.slugs[]' ifconfig m1
# mac-address mtu ipv4-address ipv4-gateway ipv6-address ipv6-gateway
```

A wrong slug is refused with that same list.

```bash
mrnctl ifconfig-set m1 eth0 ipv4-address 10.0.0.1/24
mrnctl ifconfig-set m1 eth0 mtu 1400 --restart
mrnctl defects-set  m1 eth0 inward loss 5 --no-restart
mrnctl defects-set  c1 rightward maximum-delay-ms 50
```

`defects-set` has two shapes under one verb, because the table has two: a node entry has one
level per port (`<node> <port> <inward|outward> <field>`), a cable entry has none
(`<cable> <leftward|rightward> <field>`). Which one you meant is decided by what the name
designates, not by how many arguments you typed.

Two rules follow from the GUI, not from us:

* **The value is checked exactly as the GUI checks it** — same constraints, same refusals,
  reported as `constraint_violated`. The difference is that no dialog box appears.
* **The question the GUI asks, the script must answer in advance.** When a change needs a
  running node restarted, the GUI opens a *"restart now?"* dialog. A script has nobody to ask,
  so it must carry `--restart` or `--no-restart`; without it, the answer is
  `restart_choice_required`. This applies to nodes only: a **connected cable** takes its new
  defect *hot*, with no question and no restart, because that is what the GUI already did.

Addresses set this way are real: they are read when the device is built, so they land in the
guest's boot parameters.

---

## 9. Recipe C — make the guest do the work

The channel commands the *infrastructure*. What happens **inside** a machine is commanded by
its **startup configuration** — the same feature the GUI offers under that name, reachable
from a script as `rc-set` / `rc-get`.

The content is a piece of bash the guest sources at the end of its boot. It can do the
machine's part of a lab, write a log, synchronise roughly with the others, and signal that it
is ready.

```bash
cat > /tmp/scenario.sh <<'EOF'
ip addr add 10.0.0.1/24 dev eth0 2>/dev/null
ip link set eth0 up
ping -c 3 10.0.0.2 > /mnt/hostfs/ping.log 2>&1
echo "$?" > /mnt/hostfs/ping.status

LINE='ready'
printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
  mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
  printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready
EOF

mrnctl rc-set m1 --from=/tmp/scenario.sh --enable
mrnctl start m1
mrnctl wait  m1 --ready --timeout=300

hostfs=$(mrnctl -q '.hostfs' rc-get m1)      # where the guest writes, host side
cat "$hostfs/ping.log"
```

Three things to know:

* **`/mnt/hostfs` inside the guest is a real host directory.** Whatever the guest writes
  there, your script reads directly — that is the whole return path, and it needs no network.
  `rc-get` tells you where it is.
* **The startup configuration is read when the device is built**, so it takes effect at the
  **next** start, never on a running machine.
* **The content travels in clear**, either inline (`rc-set m1 'echo hello'`) or by file
  (`--from=<absolute path>`). You never manipulate the project file to place it.

Machines, switches and routers have a startup configuration today. Hubs, clouds and the world
components do not, yet.

### Inside a router: the routing daemons

A router has more than one. Besides its UNIX one — the one you get when you name no field — it
carries **one startup configuration per routing daemon**, exactly as the router dialog carries
one tab per protocol. Ask the router which ones it has; do not assume a list:

```bash
mrnctl -q '.available | join(" ")' rc-get r1
# rc_config_unix zebra rip ripng ospf bgp ospf6 isis
```

Any of those names goes in `--field=`. Naming none keeps meaning what it meant before: the UNIX
one.

```bash
cat > /tmp/zebra.conf <<'EOF'
hostname r1
password zebra
interface eth0
 ip address 10.0.0.254/24
EOF

mrnctl rc-set r1 --from=/tmp/zebra.conf --field=zebra
mrnctl rc-get r1 --field=zebra                  # read it back, whole
```

A daemon's tab has **two** switches, and both matter:

* **enabled** — whether *your* text is used. Disabled, the daemon still gets the stock
  configuration Marionnet ships.
* **selected** — whether the daemon is configured **at all**. Unselected, its configuration file
  is moved aside at boot, so the daemon does not start.

Writing a content sets both, because a configuration that would silently go nowhere is the
surprise this channel exists to avoid. The flags let you say otherwise, one at a time:

```bash
mrnctl rc-set r1 --field=ospf  --unselect        # this daemon will not run
mrnctl rc-set r1 --field=zebra --terminal        # open its CISCO-IOS-like terminal
mrnctl -q '.selected, .terminal' rc-get r1 --field=zebra
```

The answer of `rc-set` reports `selected_before`/`selected` and `terminal_before`/`terminal`
beside `enabled_before`/`enabled`, and `changed` covers all three. On a plain startup
configuration — a machine, a switch, the UNIX one of a router — those fields are simply absent,
and the flags are refused.

---

## 10. Recipe D — read what happened

```bash
mrnctl -q '.nodes[] | select(.state=="on") | .name' ls
mrnctl ifconfig m1                       # the addresses actually configured
mrnctl history m1                        # every disk state this machine has had
mrnctl notifications                     # everything Marionnet tried to tell a human
```

`history` deserves a word, because it is the one table where the name is **not** the
identifier: a machine has as many rows as it has disk states, all bearing its name. A state is
designated by its **COW file**, which the read side already gives you, and which is what the
three write commands take:

```bash
cow=$(mrnctl -q '.rows[0].fields."File name"' history m1)
mrnctl history-set   "$cow" comment "before the students broke it"
mrnctl history-start "$cow"               # boot m1 from that exact disk state
mrnctl history-del   "$cow" --except      # keep that one, drop the siblings
```

`history-start` is the interesting one: it is *"Start in this state"* from the GUI's context
menu, and it is how a lab is replayed from a known point rather than from the beginning.

`documents` is readable only — its rows are metadata about imported files, with no identifier
to act on.

---

## 11. Recipe E — the journals

The tables of § 10 say what *Marionnet* knows. The journals say what happened **inside**: what
the boot did, whether the startup configuration failed and where, what was typed at the prompt,
and what the console and the terminal window showed.

```bash
mrnctl log m1                          # the startup configuration — the default journal
mrnctl log m1 boot --tail=40           # what the boot did before the relay was reached
mrnctl -q .content log m1 commands     # what was typed, one line per command
mrnctl -q .content log sw1             # a switch, too, journals what vde_switch answered
```

A journal is a **file**, and that is the difference with everything else in this guide: it
outlives what it describes. A machine which has been powered off still answers `log`, and a
switch answers about a `vde_switch` which is long gone.

Seven journals, of two natures — five written by the guest itself, in the hostfs directory of
§ 9, and two written by Marionnet on the host side:

| Journal | Written by | Holds |
|---|---|---|
| `rc_config` | the guest, in its hostfs | the trace of the startup configuration, its output, its errors, and the status of the command which failed. A **switch** has this one too, written by Marionnet from what `vde_switch` answered |
| `boot` | the guest, in its hostfs | what the boot did *before* the relay was reached: the kernel ring buffer, the failed units, or an excerpt of `/var/log` on an older guest |
| `commands` | the guest, at every prompt | the timestamped history of what was typed — a `#<epoch>` line before each command |
| `console` | Marionnet, host side | the console of the UML process itself, which shows a boot that never reaches the relay at all |
| `terminal` | Marionnet, host side | the recorded terminal session: the commands **and** their output, as the student saw them |
| `report` | the guest, **when asked** | the *state* of the guest at one instant: its real interfaces, its routing tables, its neighbours, `ip_forward`, and its firewall in replayable form. See `report` below |
| `exec` | the guest, **when the channel runs something** | what *this channel* was asked to run inside the guest: the command, its date and its status — never its output. It is what tells a corrector apart from a student. See `exec` below |

The three first ones are always there. `console` and `terminal` exist only if the session was
started for it (`--console-log`, `--terminal-log`, both implied by `--exam` — see below),
because recording a session in silence would be surveillance rather than teaching. And the last
two are there once somebody has asked for them: `report` once it has been asked for (or once the
guest has been shut down gracefully), `exec` once the channel has run something in that guest.

That list lives in the running Marionnet, not on this page: `help` publishes it under `logs`,
and every answer repeats, under `available`, the journals **this** component has — seven for a
machine or a router, one for a switch, none for a cable.

Because the failing line has the same shape wherever it comes from, one `grep` covers a
machine, a router and a switch:

```bash
mrnctl -q .content log m1 | grep '^!! FAILED'
```

### A missing journal is three different pieces of news

`log` refuses a file which is not there yet, and the refusal says what to do about it — whether
to wait for the guest, to start the component, or to restart Marionnet with an option:

```bash
mrnctl log m1 boot
# {"ok":false,"error":"bad_argument","detail":"\"m1\" has written no boot journal yet (…):
#  it has not been started since this project was opened, or its guest has not reached the end
#  of its boot — see wait --ready"}
```

Distinguishing those three is what lets a script decide by itself: `wait --ready` and try
again, `start` and try again, or give up and tell the human which option the session lacks.

### What the answer promises

The content comes back in the `content` field, as one JSON line like every other answer, and
two ceilings apply — they are not of the same nature:

* the **answer** carries at most 400 lines; `--tail=<n>` moves that window, and `truncated`
  says the file held more (`total_lines` says how much more);
* the **reader** stops at 2 MiB, because the file is written by a guest which has no reason to
  be reasonable.

A line which is not valid UTF-8 is dropped and **counted** (`dropped_lines`) rather than
served: the answer has to remain a single JSON line.

### What a switch knows right now

`switch-info` is the mirror of `log`. One serves what was *written*, and survives; the other
asks a running `vde_switch` what it currently *knows*, which is written down nowhere and dies
with it:

```bash
mrnctl switch-info s1                  # every table, in one round trip
mrnctl switch-info s1 macs             # or just one, positionally or with --table=

mrnctl -q '.tables[] | select(.name=="macs") | .entries[].mac' switch-info s1
```

Each table carries `entries`, parsed into fields, **and** `lines`, the switch's own words —
no parser of ours is a reason to lose them. A table the switch refused carries its code and
its message instead. Here too the names are published by `help`, as `switch_tables`.

A switch which is not running refuses, and names the other verb: what it said at startup
outlives it, and that is `log`.

### What a guest is doing right now

The other journals above are **traces**: they say what was *said* — a command was called, a
service printed something. A trace cannot say what *is*. The classic trap is a redirection:
`echo 1 > /proc/sys/net/ipv4/ip_forward` leaves `echo 1` in the trace, and nothing else, so
looking for `ip_forward` there finds nothing although forwarding is on.

`report` asks a running machine or router to describe itself. It answers that the report was
taken; the report itself is the sixth journal, read like any other:

```bash
mrnctl report m1                       # ask — answers when the guest has written it
mrnctl -q .content log m1 report       # read it
```

```bash
mrnctl -q .content log m1 report | grep 'ip_forward'
# net.ipv4.ip_forward = 1
```

It is a **snapshot**, and it says so in its own header: everything in it was true at the date
it carries, and asking again gives a new one. What it holds is what a corrector needs and no
model can know — the addresses really configured (including the ones the guest made up for
itself, which the `ifconfig` table of § 10 never sees), the routing tables for IPv4 and IPv6,
the neighbours, `ip_forward`, and the firewall in **replayable** form (`iptables-save`), which
is the section to read: `iptables -L -vv` prints unreadable pseudo-bytecode under the `nft`
backend.

The same producer also runs at a graceful shutdown, and the report then says `taken:
shutdown` instead of `taken: on-demand` — which of the two you are reading is never a guess.

`report` refuses what cannot answer, and the refusals do not say the same thing: a switch is
sent to `switch-info` (it knows things, but it runs no guest), and a machine which is off is
sent to `log … report` — the report of its last session outlives it. `--timeout=<s>` bounds
the wait, which is a wait on the *guest*: a machine still booting has nobody to answer yet.

### Making a guest do something

Everything above **observes**. `exec` is the one verb that **commands**: it runs a command line
inside a running machine or router, and answers with its status and its output.

```bash
mrnctl exec m1 uname -r
# {"ok":true,"component":"m1","command":"uname -r","status":0,"timed_out":false,
#  "output":"6.12.95\n","lines":1,…,"journal":"exec"}

mrnctl -q .output exec m1 -- ping -c 1 -W 2 10.16.16.3
```

Two things about that second line are worth reading twice.

The bare `--` **ends the options of the channel**. Options are recognised wherever they stand in
a request (`rc-set m1 <content> --field=zebra` puts one last), so without the separator, the
`-W 2` would be fine but a `--all` would be taken by the channel for one of its own and the guest
would run a mutilated command. Rather than doing that silently, `exec` refuses an option it does
not know, and the refusal names the separator.

And the command is handed to the guest's shell **as it was received**, quoting included — what
this channel never does is parse the line itself. But *received* is the operative word: a request
is one line of text, so the quoting has to survive **your own shell** first. Pass a composite
command as a single argument:

```bash
mrnctl exec m1 "sh -c 'exit 7'"     # status 7 — the guest's shell reads the quotes
mrnctl exec m1 -- sh -c 'exit 7'    # status 0 — your shell ate them, the guest ran `exit'
```

The rule is the same one batch files rest on (§ 13): the tail of the line is free text, and
nothing between you and the guest re-quotes it for you.

`--timeout=<s>` bounds the command *inside the guest*: when it expires, the command is killed
there and the answer says so (`status: 124`, `timed_out: true`) with whatever output it had
produced — rather than the channel giving up on an answer that would never come. The output is
capped at 200 lines (`truncated`, `total_lines`), because an output is a value, not a document.

Whatever is run this way is written to the `exec` journal, and that is its reason to exist: what
the **channel** injected must never be mistaken for what the **student** typed (which is the
`commands` journal). Two writers, two files:

```bash
mrnctl -q .content log m1 exec
# ## exec 39821.1786564002293.0 (2026-08-12T19:46:43Z): ping -c 1 -W 2 10.16.16.3
# ## 5 line(s) of output in 0s
```

The honest limit is the same one the hostfs journals carry: this exchange goes through the
hostfs directory, which the guest can write, so a determined student could forge an answer. Only
the console (and the terminal recording) are out of the guest's reach. For marking, that is the
difference between an observation and a proof.

### Recording a session

Two options at startup, both implied by `--exam`:

| Option | What it records |
|---|---|
| `--console-log` | the console of each virtual machine, into the project's directory |
| `--terminal-log` | the terminal session of each virtual machine, replayable with `scriptreplay` |

They matter for two different reasons. A console shows a boot which never gets far enough to
write anything in a hostfs — the failure a script cannot otherwise see. And both are written
by the host, hence out of the guest's reach, where the three journals of the hostfs are
writable from inside the guest: of those two, the terminal recording is the one that holds the
commands together with their output, which is what makes marking defensible. On the exam mode
itself, what it archives into the project file, and how those archives are read from the
interface — the Markdown report opens rendered, its source one gesture away — see
`doc-src/exam-mode.md`.

---

## 12. The windows that open by themselves

Marionnet sometimes opens a window nobody asked for: the splash screen, the summary of what
had to be adapted when loading an old project, an error. In a driven session there is nobody
to close them, and a modal dialog would block everything.

Script mode therefore **captures and closes them**, and keeps what they said:

```bash
mrnctl notifications                  # everything captured so far
mrnctl notifications --since=3        # only what is new
mrnctl notifications --clear
```

`open` also returns, in a `notifications` field, whatever popped up while it was loading — so
a project that had to be adapted tells you so in the answer, instead of silently.

Two options exist for the rare case where you want the old behaviour back:
`--keep-dialogs` leaves the windows on screen as usual, and `--dialog-timeout=N` changes how
long a captured window is given before it is closed.

---

## 13. Batch mode

One command per line, read from a file or from standard input:

```bash
cat > lab.mrn <<'EOF'
new /tmp/lab.mar
add machine m1
add machine m2
add switch s1 --ports=4
connect c1 m1:eth0 s1:port1
connect c2 m2:eth0 s1:port2
save-as /tmp/lab.mar
EOF

mrnctl -f lab.mrn
mrnctl -f -  < lab.mrn
```

Batch mode **stops at the first refusal** — which is what you want when each line depends on
the one before. `--keep-going` runs the rest anyway.

Batch mode is a convenience of transport, not of semantics: each line is still a separate
request with its own answer, and a failure in the middle leaves the project in the state the
successful lines put it in. **There is no transaction** — which is exactly why the next section
exists.

### Checking a `.mrn` before sending it

`mrn-check` reads the file and sends nothing:

```bash
mrn-check lab.mrn
# lab.mrn: 9 request(s), no error

mrn-check broken.mrn
# broken.mrn:6: error — a switch numbers its ports from 1, so "port0" does not
#               exist (its first port is port1)
# broken.mrn:7: error — "m3" is declared by no add
# broken.mrn: 2 error(s), 0 warning(s)
```

Exit codes: `0` valid, `1` errors found, `2` nothing could be checked.

**It does not hold a copy of the grammar either.** It asks the running Marionnet, exactly as
you would (`help`). To check without a running Marionnet — in an editor, in CI, before
launching anything — take a snapshot once and point at it:

```bash
mrnctl help > grammar.json
mrn-check --grammar=grammar.json lab.mrn
```

A snapshot is a *cache*. If it ages, the file it validates may be checked against a vocabulary
Marionnet no longer serves; retake it rather than edit it.

What it checks beyond the verb and its arity: names already taken, components referenced before
being added, port names (a machine numbers its interfaces from 0, a switch its ports from 1),
ports outside the declared `--ports=`, ports already taken by an earlier cable.

Those checks need to know what exists, so they are only applied when the file **builds the
project itself**, that is from a `new`. After an `open`, or with no project command at all, the
file leans on a project `mrn-check` cannot see: it then checks the syntax and the port names,
says so in a `note`, and does not invent errors about names it has no way to know.

It is a *lint*, not a promise: it catches what can be decided by reading, and leaves to the
channel what only the running model can answer (whether a machine may be started right now,
whether a value satisfies a treeview constraint).

### Turning a `.mrn` into a shell script

A `.mrn` says **what** a lab is. A shell script says what to **do** with it — wait for a guest,
capture a result, loop over the machines. `mrn2sh` is the door from one to the other:

```bash
mrn2sh lab.mrn > lab.sh && chmod +x lab.sh
./lab.sh                     # same effect as: mrnctl -f lab.mrn
./lab.sh /tmp/other.mar      # …on another project file
```

`mrn2sh` is `mrn-check --to-bash` under another name, and that is not packaging: **the check is
a precondition of the translation.** A file with an error produces no script at all — a script
built on a faulty source would be faulty too — and the diagnostics go to standard error so the
script itself stays clean on standard output.

The result is a plain, readable script: a preamble (`set -euo pipefail`, a socket guard, a `ctl`
helper that echoes each request), your comments where you put them, one `ctl` call per request,
and the project path hoisted into `PROJECT="${1:-…}"` when the file names exactly one — so the
script takes an optional `.mar` argument. Nothing else is invented: the translation never adds a
`wait` you did not ask for.

**Why a tool rather than `sed`.** Because a free-tail argument may hold spaces, and only the
arity says where it starts:

```
rc-set m1 echo "hello world" >> /mnt/hostfs/log     # in the .mrn
```
```bash
ctl rc-set m1 'echo "hello world" >> /mnt/hostfs/log'    # what mrn2sh emits
ctl rc-set m1 echo "hello world" >> /mnt/hostfs/log      # what a sed emits — and it redirects!
```

The translation is **one-way**. Once you have edited `lab.sh`, it is the source; regenerating
overwrites it, and the generated header says so.

---

## 14. Asserting a lab

A `.mrn` says what a lab **is built of**. A `.mrv` says what must be **true of it** — and
`mrn-verify` reads one against a running session:

```bash
cat > lab.mrv <<'EOF'
# the lab of § 13, once it runs
state m1 is on
field s1 port_no is 4
cable c1 m1:eth0 s1:port1
switch s1 vlans has vlan=6 ports.port=3
journal m1 rc_config ok
report m1 says ~ net[.]ipv4[.]ip_forward *= *1
EOF

mrn-verify lab.mrv
# PASS  state m1 is on
# FAIL  field s1 port_no is 4
#       s1.port_no is "8"
# …
# 5 passed, 1 failed, 0 skipped.
```

`mrn-verify --help` lists the assertions it understands — nine families, no more: they are the
ones the channel can serve, and each came from a real lab. Nothing in the project is modified;
the only request that is not a pure read is `report`, which asks a *guest* to describe itself
(`--refresh=never` reads the last report instead, which is what marking a session already over
means).

### Three verdicts, and why the third one matters

| Verdict | Meaning |
|---|---|
| `PASS` | the channel was asked, and it says the assertion holds |
| `FAIL` | the channel answered, and its answer contradicts the assertion |
| `SKIP` | the channel offers **no way to know** — and the reason says which |

The distinction is the point of the tool, and `reaches` is where it was born. That assertion —
the connectivity three of the five labs behind this design need — was written before anything
could answer it, and refused **by name**: a verifier that returned `FAIL` there would have failed
a student for a limit of the tool. Against a Marionnet which does not publish `exec`, that is
still what happens, and the reason is named:

```
SKIP  reaches m1 m2
      this Marionnet publishes no `exec' verb: the channel offers no way to know
```

That sentence is not a fixed string: the tool looks the verb up in what `help` publishes. Since
the channel learned to run a command inside a guest, the same file is *answered* — `reaches`
pings from inside the first component, and the target may be another component (whose address is
then read from its own report, the only place a real address exists) or an address written out:

```
PASS  reaches m1 h3
FAIL  reaches m1 10.16.16.99
      m1 -> 10.16.16.99: 1 packets transmitted, 0 received, 100% packet loss
SKIP  reaches m1 h3
      cannot ask h3 where it lives: "h3" is off: a report is taken *inside* a running guest…
```

The third line is the same assertion as the first, with `h3` powered off: not knowing where to
ping is a limit of what can be observed, never a false network. Use `--strict` when you want a
lab that is *entirely* provable — a `SKIP` then counts as a failure.

Exit codes: `0` everything holds, `1` at least one `FAIL` (or the file has an error), `2` nothing
could be checked. `--json` prints one object per assertion, with its line and its reason — the
form to consume from a script or an agent.

### The assertion that looks the same and is not

Two of these lines seem to say the same thing about a machine, and they do not:

```
journal m1 rc_config contains ip_forward
report  m1 says     ~ net[.]ipv4[.]ip_forward *= *1
```

The first reads the **trace** of the startup configuration, the second the **state** of the guest.
A configuration written the ordinary way — `echo 1 > /proc/sys/net/ipv4/ip_forward` — leaves only
`echo 1` in the trace, because `set -x` does not trace redirections. So on a machine where
forwarding *is* enabled, the first assertion fails and the second passes. A correction key built
on the first would be wrong; use the trace to prove that a command was **called** (and `journal
… ok` that none failed), and the report to prove what **is**.

### Before there is anything to ask

The file itself can be checked without a session, against a snapshot of the vocabulary:

```bash
mrnctl help > grammar.json
mrn-verify --grammar=grammar.json lab.mrv     # checks the file, asks nothing
```

Offline it also names what this vocabulary could not answer (a journal it does not serve, a
switch table it does not know, connectivity) — the same information that would come back as a
`SKIP`, said early enough to fix the file.

---

## 15. When it does not work

| Symptom | Cause and cure |
|---|---|
| `no control socket` (exit 2) | neither `--socket=` nor `$MARIONNET_CONTROL_SOCKET` is set |
| `not a unix socket: …` (exit 2) | the path is wrong, or Marionnet was started without `--control-socket` — nothing is listening there, and there never was |
| `no answer from …` (exit 3) | the socket file exists but nobody answers: Marionnet is gone and left it behind, or it is stuck in a modal dialog |
| exit 3 after a long request | the GUI thread is busy; retry with a larger `--timeout=` — the transport sizes itself on it automatically |
| `no_active_project` | open or create a project first; the network only exists inside one |
| `unsaved_changes` | say `--save` or `--no-save` explicitly; the channel will not guess |
| `forbidden_transition` | ask `can <component>` first — the state machine is the same one the GUI obeys |
| `restart_choice_required` | add `--restart` or `--no-restart` to the write |
| `timeout` on `wait … --ready` | the guest never wrote the marker: check the startup configuration is `--enable`d, and that the machine really booted (`wait --state=on` first) |

A request that carries `--timeout=N` sizes the client's own transport wait accordingly, so you
never have to configure both.

---

## 16. Going further

* `mrnctl help` — the vocabulary, always current.
* `mrnctl --help` — the client's own options.
* `mrn-check --help` — checking a `.mrn` before sending it (§ 13).
* `mrn-verify --help` — the assertions of a `.mrv`, and what each one rests on (§ 14).
* `doc-src/exam-mode.md` — the exam mode: what a session records, and what ends up in the
  project file (for the teacher, with or without this channel).
* `docs/pilotage-par-script.md` — the design of the channel, its rationale, and the journal of
  how it was built (in French, developer audience).
* `docs/journalisation-profonde.md` — the design of the journals of § 11 (in French, developer
  audience).
* `doc-src/scripting/examples/` — the scripts of this guide, runnable as they are.

### How this guide stays true

It states the *shape* of the channel and the *invariants* — the contract with the state
machine, `accepted` vs done, the ready marker, one field at a time. Those are decisions, and
they change rarely. It does **not** restate the command list, the arities or the option names
of individual verbs: those live in the server and are served by `help`. When in doubt, `help`
wins over this page.
