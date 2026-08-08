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
   [§ 11](#11-the-windows-that-open-by-themselves));
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

Machines, switches and routers have a startup configuration today (the router has one variant
per routing protocol, selected with `--field=`). Hubs, clouds and the world components do not,
yet.

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

## 11. The windows that open by themselves

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

## 12. Batch mode

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

---

## 13. When it does not work

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

## 14. Going further

* `mrnctl help` — the vocabulary, always current.
* `mrnctl --help` — the client's own options.
* `mrn-check --help` — checking a `.mrn` before sending it (§ 12).
* `docs/pilotage-par-script.md` — the design of the channel, its rationale, and the journal of
  how it was built (in French, developer audience).
* `doc-src/scripting/examples/` — the scripts of this guide, runnable as they are.

### How this guide stays true

It states the *shape* of the channel and the *invariants* — the contract with the state
machine, `accepted` vs done, the ready marker, one field at a time. Those are decisions, and
they change rarely. It does **not** restate the command list, the arities or the option names
of individual verbs: those live in the server and are served by `help`. When in doubt, `help`
wins over this page.
