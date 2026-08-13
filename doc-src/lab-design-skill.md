# Designing, running and grading a Marionnet network lab

*A skill for an AI agent — any agent that can run shell commands and read their output. It is
not written for one assistant in particular, and it needs no plug-in: everything below is
`marionnet-ctl` and four small scripts shipped with Marionnet.*

---

## When this applies

Use this page when you are asked to do any of these, for a teacher or for yourself:

* **design** a network lab (*travaux pratiques*): a topology, a statement for the students, and
  a correction key;
* **build** one in Marionnet without clicking, and hand back a `.mar` file that replays;
* **run** one and watch what happens inside the virtual machines;
* **check** a student's session — a lab in progress or an exam already over — and produce a
  defensible mark with the evidence that supports it;
* **debug** a lab that does not behave as its author expected.

You are driving a **real** simulator: the machines are real Linux kernels, the switches are real
`vde_switch` processes, and the cables carry real frames. Nothing here is mocked, so nothing here
is instant.

**Prerequisites.** A Marionnet started with `--control-socket`, the client `marionnet-ctl` (also
installed as `mrnctl`), and `socat`; `jq` for anything that reads an answer. The three companion
tools — `mrn-check`, `mrn2sh`, `mrn-verify` — sit next to the client.

**Background reading, in this order:** `doc-src/scripting/README.md` (the shape of the channel,
its invariants, and complete recipes) and `doc-src/exam-mode.md` (what an exam session records).
This page assumes them and does not repeat them; it adds the part neither of them covers — how to
go from a *statement* to a *mark*.

---

## 0. Five directives

These five are not style. Each of them was paid for by a measurement, and breaking one produces
work that looks right and is wrong.

### 1. The grammar is not yours to remember — ask for it

```bash
mrnctl help                 # every verb, its syntax, its arity
mrnctl help connect         # one of them
```

The running Marionnet is the **single source of truth** for its own vocabulary. Never write a
verb's arity or option list from memory into a script, a lint, a completion or a document: a
second copy is the one that drifts. This page names verbs (§ 1) because an agent that does not
know what exists cannot design; it deliberately gives **no arity and no option list**, and a
bench compares its list of names against `help` — if the two ever disagree, `help` wins.

The same rule covers the names that are *not* verbs: journal names (`help` publishes them under
`logs`), switch tables (`switch_tables`), component kinds (`kinds`), the action names of `can`
(`actions`), and the writable field names of a table — every read answer carries its own `slugs`.
Ask; do not assume.

### 2. The channel may do only what the GUI may do

It is not a back door. A component that cannot be deleted while it runs cannot be deleted by you
either. Ask before acting rather than provoking a refusal:

```bash
mrnctl can m1                                   # what is allowed on m1 right now
mrnctl -q '.can | index("del") != null' can m1  # true / false
```

Treat `forbidden_transition` as a bug in your script. The one deliberate exception is **cables**:
they are edited and removed while the network runs, because that is what you do with real
hardware.

### 3. `accepted` is not `done`

A transition answers `{"accepted":true}` — *the request was legal and handed over* — never *it is
finished*. Booting a Debian guest takes seconds and sometimes a minute. Two different waits:

```bash
mrnctl wait m1 --state=on --timeout=120     # the UML process runs
mrnctl wait m1 --ready    --timeout=300     # the guest itself says it is ready
```

`--ready` only works if the guest writes the marker (§ 2.3). A lab whose scenario does not write
it is a lab you can only wait for by sleeping, which is how flaky benches are born.

### 4. `SKIP` is not `FAIL`

`mrn-verify` answers three verdicts, and the third one carries the ethics of the whole exercise:
`PASS` (asked, and it holds), `FAIL` (asked, and the answer contradicts it), `SKIP` (**the
channel offers no way to know** — and the reason says which). A machine that is off cannot say
where it lives; that is not a wrong network, it is an unanswerable question.

**Never turn a limit of the tool into a student's mistake.** When you write your own checks,
reproduce that distinction explicitly; when you report a mark, report the skips.

### 5. A mark rests on what the *host* wrote

Of the seven journals, five live in the guest's shared directory — which the student can write.
Two are written by Marionnet on the host, out of the guest's reach. See § 3.2 before you let a
grade depend on a file.

---

## 1. What exists, by intent

Forty-three verbs, grouped by what you want. **Names only** — for the syntax, `help <verb>`.

### Session and vocabulary

| Verb | Use it to | Example |
|---|---|---|
| `help` | learn the vocabulary, and check a verb exists before relying on it | `mrnctl help exec` |
| `status` | know whether a project is open at all | `mrnctl -q '.active' status` |
| `notifications` | read the windows script mode captured and closed for you | `mrnctl notifications --since=3` |
| `quit` | end the session (it saves nothing by itself) | `mrnctl quit` |

### The project

| Verb | Use it to | Example |
|---|---|---|
| `new` | create the project every component needs | `mrnctl new /tmp/lab.mar --no-save` |
| `open` | load a `.mar` — a student's session, for instance | `mrnctl open /srv/exams/dupont.mar` |
| `save` / `save-as` | write the deliverable | `mrnctl save-as /tmp/lab.mar` |
| `close` | close it, stating what to do with the changes | `mrnctl close --no-save` |

`new`, `open` and `close` refuse to throw away work: without `--save` or `--no-save` on a
modified project you get `unsaved_changes`. State your intent; the channel will not guess.

### The model — topology

| Verb | Use it to | Example |
|---|---|---|
| `add` | create a component of any published kind | `mrnctl add router r1 --ports=2` |
| `del` | remove one | `mrnctl del m3` |
| `rename` | rename one (never a cable) | `mrnctl rename m1 client` |
| `connect` | cable two ports | `mrnctl connect c1 m1:eth0 s1:port1` |
| `get` / `set` | read or write one field of a component | `mrnctl get r1 port_no` |
| `ls` | list, optionally filtered | `mrnctl ls --kind=machine --can=start` |
| `can` | ask what is allowed right now | `mrnctl can` |

**Port names follow the GUI, and the three conventions differ**: a machine numbers its interfaces
from **0** (`eth0`), a **router** its ports from **0** (`port0`), a switch or a hub from **1**
(`port1`). A refusal lists the free ports, so nothing has to be guessed. A crossover cable is
`connect c3 m1:eth0 m2:eth0 --crossover`.

### The four tables of the GUI

| Verb | Use it to | Example |
|---|---|---|
| `ifconfig` / `ifconfig-set` | read or write declared addresses, one field at a time | `mrnctl ifconfig-set m1 eth0 ipv4-address 10.0.1.1/24` |
| `defects` / `defects-set` | inject loss, delay, duplication — on a port or on a cable | `mrnctl defects-set c1 rightward maximum-delay-ms 50` |
| `history` / `history-set` / `history-start` / `history-del` | address a machine's **disk states** | `mrnctl history-start "$cow"` |
| `documents` | list what the exam mode archived | `mrnctl -q '.rows[].fields.Title' documents` |

Three things save time here. A field is written by the **slug** of its column, and every read
answer carries the accepted slugs beside its columns (`mrnctl -q '.slugs[]' ifconfig m1`). A write
that would need a running node restarted must carry `--restart` or `--no-restart`, because the
dialog the GUI would open has nobody to answer it. And in `history` the identifier is not the
name but the **COW file**, which the read side gives you: `history-start` is *"start in this disk
state"*, the way a lab is replayed from a known point instead of from the beginning.

### What happens inside a guest

| Verb | Use it to | Example |
|---|---|---|
| `rc-set` | give a component the bash it runs at the end of its boot | `mrnctl rc-set m1 --from=/tmp/scenario.sh --enable` |
| `rc-get` | read it back — and learn where its shared directory is | `mrnctl -q '.hostfs' rc-get m1` |

Machines, routers and switches have a startup configuration; hubs, clouds and the world
components do not. A **router carries one per routing daemon** besides its UNIX one — ask which
ones rather than assuming (`mrnctl -q '.available|join(" ")' rc-get r1`) and name one with
`--field=`. Two switches on a daemon's tab matter and are set together by default: *enabled*
(your text is used) and *selected* (the daemon is configured at all).

The content is read **when the device is built**, so it takes effect at the **next** start, never
on a running machine.

### Life and synchronisation

| Verb | Use it to | Example |
|---|---|---|
| `start` `stop` `suspend` `resume` `poweroff` `restart` | drive one component | `mrnctl start r1` |
| `start-all` `shutdown-all` `poweroff-all` | drive the whole lab | `mrnctl shutdown-all` |
| `wait` | wait for one component's state, or for its guest | `mrnctl wait m1 --ready --timeout=300` |
| `wait-all` | wait for every component to reach a state | `mrnctl wait-all --state=off --timeout=180` |

`shutdown-all` is the graceful one and is what an exam session needs (§ 5); `poweroff-all` is the
power cut, and it archives nothing.

### Observation — what happened, and what is

| Verb | Use it to | Example |
|---|---|---|
| `log` | read one of the seven journals of a component | `mrnctl -q .content log m1 boot --tail=40` |
| `switch-info` | ask a **running** switch what it knows right now | `mrnctl switch-info s1 macs` |
| `report` | ask a **running** guest to describe its own state | `mrnctl report r1 --timeout=90` |

`log` serves files, so it outlives what it describes: a machine that has been powered off still
answers. `switch-info` and `report` ask a live process, so they die with it. `report` answers
that the report was taken; the report itself is read back as the journal of the same name.

### The one verb that commands

| Verb | Use it to | Example |
|---|---|---|
| `exec` | run a command line inside a running machine or router | `mrnctl exec m1 -- ping -c 1 -W 2 10.0.2.1` |

This is the only way to obtain a statement about **connectivity**: a report describes a *state*,
never a *reachability*. Read § 4.3 before writing one into a correction key.

---

## 2. The lifecycle, and the file of each step

```
   statement            lab.mrn ──mrn-check──▶ mrnctl -f ──▶ .mar        (design & build)
       │                                                      │
       │                 scenario.sh ──rc-set──▶ guest ◀───────┘          (configure)
       ▼                                          │
   key.mrv ◀────────────────────────── start / wait --ready                (run)
       │                                          │
       └──────── mrn-verify ◀── log · report · switch-info · exec          (observe & assert)
                                                  │
                              --exam ──▶ documents inside the .mar         (record & archive)
```

| Artefact | What it is | Made by | Checked by |
|---|---|---|---|
| `lab.mrn` | the lab as a list of requests, one per line | you | `mrn-check lab.mrn` |
| `lab.mar` | the lab itself — **Marionnet is its only legitimate producer** | `save-as` | replaying it: `marionnet -r lab.mar` |
| `scenario.sh` | the bash a guest runs at the end of its boot | you | `journal … ok` after the run |
| `key.mrv` | what must be **true** of the lab | you | `mrn-verify --check-only key.mrv` |
| `lab.sh` | `mrn2sh lab.mrn` — when the lab needs waiting, looping, capturing | `mrn2sh` | it is a shell script |
| journals, documents | what the session produced | Marionnet and the guests | § 3 |

Two rules about these files:

* **Never write a `.mar` yourself, and never edit one.** It is Marionnet's own format. A lab is
  built through the channel and written by `save-as`.
* **`mrn-check` before `mrnctl -f`, always.** Batch mode stops at the first refusal but there is
  **no transaction**: a failure in the middle leaves the project half-built. The lint catches
  what can be decided by reading — arity, a name used before it is added, a port that does not
  exist, a port already taken.

### 2.3 The ready marker

Marionnet cannot know when a guest is ready; only the guest knows. The convention is one line:
the scenario writes `/mnt/hostfs/marionnet-guest-ready`, atomically, and `wait --ready` reports
its first line back to you — so a guest can return a *verdict*, not merely its presence. Do not
rename that file: the guest relay sources everything matching `/mnt/hostfs/…relay*`, and a marker
falling into that glob would be executed as bash.

Put this at the end of every scenario you write:

```bash
LINE='ready'
printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
  mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
  printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready
```

---

## 3. What is provable, and by what

### 3.1 The evidence table

| A correction key wants to say | Ask | Nature |
|---|---|---|
| the topology is the one of the statement | `ls`, `get`, `ifconfig`, the cables | **model** — true by construction |
| this router has three interfaces | `get r1 port_no` | model |
| VLAN 6 exists and port 3 is in it | `switch-info s1 vlans` | **live state** of the switch |
| this switch has learnt m1's MAC | `switch-info s1 macs` | live state |
| the startup configuration ran without failing | `log <c> rc_config`, no `^!! FAILED` | **trace** |
| this command was *called* at boot | `log <c> rc_config` | trace |
| the student typed these commands | `log <c> commands` | trace, guest-written |
| the boot itself failed before anything else | `log <c> boot`, `log <c> console` | trace |
| forwarding is on **right now** | `report <c>`, then `log <c> report` | **state** |
| these are the addresses really configured | `report <c>` | state |
| this firewall rule is loaded | `report <c>`, the `iptables-save` section | state |
| m1 reaches m2 | `exec m1 -- ping …`, or `reaches` in a `.mrv` | **experiment** |
| the student saw this on their terminal | `log <c> terminal`, the exam archive | host-written evidence |

Anything not in that table is not observable from the channel. Say so rather than inventing a
proxy: a proxy that is *nearly* the same thing is how a student gets marked down for something
they did right.

### 3.2 The hierarchy of evidence — this decides what a mark may rest on

1. **Written by the host, out of the guest's reach**: `console` and `terminal` (the recorded
   session, commands *and* their output). Only these two are evidence in the strong sense.
2. **Written by the guest, in a directory the student can write**: `rc_config`, `boot`,
   `commands`, `report`, `exec`. Excellent for understanding, insufficient on their own for a
   contested mark.
3. **The model** (`ls`, `get`, tables): true by construction, and says nothing about what
   happened inside.

The `exec` journal exists for one reason: what **you** injected while marking must never be
confused with what the **student** typed (`commands`). Two writers, two files. It is not archived
into the project, for the same reason.

---

## 4. Writing the correction key

A `.mrv` is one assertion per line, `#` comments ignored, played against a live session by
`mrn-verify`. `mrn-verify --help` lists the families it understands — **nine, no more**, each of
which came from a real lab. Ask it rather than reciting them here.

### 4.1 From a statement to assertions

Take each sentence of the statement that the student can get *wrong*, and decide what would make
you believe it. Typical mapping:

| The statement says | The key asserts | Family |
|---|---|---|
| "connect m1 to the switch's first port" | the cable exists between those two ports | `cable` |
| "the router has two interfaces" | the field of the model | `field` |
| "put port 3 in VLAN 6" | the switch says so | `switch` |
| "configure the interfaces of m1" | the guest's own view of its addresses | `report … says` |
| "enable forwarding on r1" | the guest's own view of `ip_forward` | `report … says` |
| "your configuration must run without error" | no failing line in the journal | `journal … ok` |
| "block ICMP from the outside" | the rule is loaded **and** the ping fails | `report … says` + `reaches` |
| "m1 must reach m2" | the experiment | `reaches` |
| "leave the machine shut down properly" | the archives exist | `documents … has` |
| "the machine must be running at the end" | the model | `state` |

### 4.2 The two assertions that look alike and are not

```
journal m1 rc_config contains ip_forward
report  m1 says     ~ net[.]ipv4[.]ip_forward *= *1
```

The first reads the **trace**, the second the **state**. A configuration written the ordinary way
— `echo 1 > /proc/sys/net/ipv4/ip_forward` — leaves only `echo 1` in the trace, because `set -x`
does not trace redirections. So on a machine where forwarding *is* enabled, the first fails and
the second passes. **A key built on the first is wrong.**

Use the trace to prove that a command was *called*, and `journal … ok` to prove that none failed.
Use the report to prove what *is*.

### 4.3 Connectivity

`reaches <component> <component>|<address>` pings from **inside** the first one. Given a
component as target, it reads that target's address from **its own report** — the only place a
real address exists — so the target must be running; otherwise you get a `SKIP` that names what
is missing (the address, never the network). Given an address written out, it pings that.

### 4.4 Running the key

```bash
mrn-verify --check-only key.mrv                 # the file is well formed
mrn-verify key.mrv                              # play it against the live session
mrn-verify --json key.mrv > verdicts.json       # one object per assertion — consume this
mrn-verify --strict key.mrv                     # a SKIP counts as a failure
mrn-verify --refresh=never key.mrv              # mark a session already over: read the last report
```

Exit codes: `0` everything holds, `1` at least one `FAIL` (or the file has an error), `2` nothing
could be checked. **Consume `--json`**, not the printed lines: it carries each assertion's line
number and its reason.

Offline, against a snapshot (`mrnctl help > grammar.json`), `mrn-verify --grammar=grammar.json`
checks the file *and* names in advance what this vocabulary could not answer — the same
information a `SKIP` would give you, early enough to fix the key.

---

## 5. Grading an exam session

An exam session is `marionnet --exam`. It implies `--console-log` and `--terminal-log`, and at the
**graceful shutdown** of each machine it archives four documents into the project itself: the
report, the history of typed commands, the console, and the terminal recording. Saving the `.mar`
saves them.

A procedure that holds up:

```bash
# 1. Open the student's project WITHOUT --exam: you are the teacher now, and the source
#    windows become editable so that you can annotate a report.
marionnet --control-socket /tmp/mark.sock /srv/exams/dupont.mar &
export MARIONNET_CONTROL_SOCKET=/tmp/mark.sock

# 2. What did the session leave behind? (nothing = the machines were never shut down)
mrnctl -q '.rows[].fields.Title' documents

# 3. Replay it if the key needs live facts, then play the key.
mrnctl start-all
mrnctl wait-all --state=on --timeout=300
mrn-verify --json key.mrv > verdicts.json

# 4. Or, for a session already over, mark on what it recorded — asking no guest anything:
mrn-verify --refresh=never --json key.mrv > verdicts.json
```

What to keep in the mark sheet, for every assertion: its verdict, the **reason** the tool gave,
and which of the three levels of § 3.2 the evidence came from. A `FAIL` whose evidence is
guest-written is a *finding*, not yet a sanction: quote the terminal recording next to it, or
lower your claim.

Four limits, measured rather than assumed — none of them is the student's fault:

* **a machine that was not shut down leaves nothing** in the project: powering the project off
  brutally skips the archiving;
* **old SysV guest images produce no report** at shutdown (their init halts immediately on the
  shutdown gesture). Their history, console and terminal are unaffected — and `report` *on
  demand*, during the session, still answers;
* archiving is the **last** thing a shutdown does, so it lands a moment after the icon goes grey:
  `wait <c> --state=off` is not enough to read `documents`, wait for the row;
* the only router image currently shipped dates from 2014 and does not boot on recent hosts.

---

## 6. Traps, every one of them measured

Each of these has cost a debugging session already. The counter-rule is the second half.

| Trap | Counter-rule |
|---|---|
| **`set -x` does not trace redirections.** `echo 1 > /proc/…/ip_forward` leaves `echo 1` and nothing else | prove configuration with `report`, never by grepping a trace (§ 4.2) |
| **`\|\| true` makes the journal silent.** A failure absorbed on the left of `\|\|` never reaches the error trap | do not write `\|\| true` in a scenario you intend to check; `journal … ok` is weaker than it looks |
| **`rc-set` is refused on a running machine** (`forbidden_transition`) | you cannot even place a probe on a live guest: use `exec`, or restart |
| **A switch's startup configuration is captured at its first start only.** A later `rc-set` is accepted, `rc-get` returns the new text, and the next start replays the old one — silently | a lab needing two switch configurations uses **two switches** |
| **The quoting of an `exec` command line does not survive your own shell.** `exec m1 -- sh -c 'exit 7'` returns 0; `exec m1 "sh -c 'exit 7'"` returns 7 | pass a composite command as **one argument**; use `--` to end the channel's own options |
| **Ports are counted differently on each side.** Marionnet says `port1…portN`, `vde` numbers them `0001…` | an assertion about "port 2" must say which numbering it means; read `switch-info` output rather than computing it |
| **`iptables -L -vv` is unreadable under the `nft` backend** (pseudo-bytecode) | read the `iptables-save` section of the report — that is why it is there |
| **A journal has a ceiling**: 400 lines per answer (`--tail=` moves the window, `truncated` says there was more), 2 MiB for the reader | never conclude from an untested `grep` on a truncated answer; check `truncated` |
| **`exec` output is capped at 200 lines** and its `--timeout` kills the command *inside* the guest (`status: 124`, `timed_out: true`) | an output is a value, not a document: if you need a document, have the guest write a file and read the journal |
| **`radvd` starts but emits no router advertisement** on this host | IPv6 **global** autoconfiguration is not playable here; link-local addressing is |
| **A missing journal is three different pieces of news** | read the refusal: wait for the guest, start the component, or restart Marionnet with the option it names |

---

## 7. Worked example — a lab, designed, played and marked

A small but complete lab. Everything below runs as it is.

> **Why the forwarding node is a machine and not a `router` component.** Marionnet has a real
> router kind, and a real lab uses it — with one startup configuration per routing daemon (§ 1).
> But the only router image currently shipped dates from 2014 and does not boot on recent hosts,
> so an example built on it could not be *played*, only read. A machine with two interfaces
> forwards exactly the same way. Everything else below is unchanged by the substitution.

### 7.1 The statement given to the student

> Two LANs, `10.0.1.0/24` and `10.0.2.0/24`, are joined by `r1`.
> 1. Address `m1` on the first LAN and `m2` on the second; each takes `r1` as its gateway.
> 2. Configure `r1` so that it forwards between its two interfaces.
> 3. Show that `m1` reaches `m2`.
> 4. Shut your machines down properly before leaving.

### 7.2 The lab — `lab.mrn`

```
new /tmp/routing-lab.mar --no-save

add machine m1
add machine m2
add machine r1 --ports=2
add switch  s1 --ports=4
add switch  s2 --ports=4

connect c1 m1:eth0 s1:port1
connect c2 r1:eth0 s1:port2
connect c3 m2:eth0 s2:port1
connect c4 r1:eth1 s2:port2

ifconfig-set m1 eth0 ipv4-address 10.0.1.1/24
ifconfig-set m1 eth0 ipv4-gateway 10.0.1.254
ifconfig-set m2 eth0 ipv4-address 10.0.2.1/24
ifconfig-set m2 eth0 ipv4-gateway 10.0.2.254

save-as /tmp/routing-lab.mar
```

```bash
mrn-check lab.mrn && mrnctl -f lab.mrn
```

The addresses given here are the **declared** ones — they land in the guests' boot parameters,
and they are what a student finds already configured. For a lab where addressing *is* the
exercise, leave them out and let the student do it: what they end up with is then read from the
report, never from the `ifconfig` table (which only ever holds the declared value).

### 7.3 What the router does at boot — `r1-scenario.sh`

```bash
# r1: forward between the two LANs.
ip addr add 10.0.1.254/24 dev eth0
ip addr add 10.0.2.254/24 dev eth1
ip link set eth0 up
ip link set eth1 up
sysctl -w net.ipv4.ip_forward=1          # not `echo 1 > …`: see the trap about redirections

LINE='ready'
printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
  mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
  printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready
```

```bash
mrnctl rc-set r1 --from=/tmp/r1-scenario.sh --enable
```

Had `r1` been a `router` component, the model would name its ports `port0` and `port1` while the
guest would still call its interfaces `eth0` and `eth1`: the first pair is the GUI's view, the
second the guest's. On a machine the two coincide.

### 7.4 The correction key — `key.mrv`

```
# --- the model: true by construction, no guest needed -------------------------
state  r1 is on
field  r1 port_no is 2
cable  c1 m1:eth0 s1:port1
cable  c2 r1:eth0 s1:port2

# --- the switch, live ---------------------------------------------------------
switch s1 ports has port=2

# --- the traces: the configuration ran, and nothing in it failed --------------
journal r1 rc_config ok
journal r1 rc_config contains ip_forward
journal r1 rc_config lacks Cannot

# --- the state, taken inside the guest ----------------------------------------
report r1 says ~ net[.]ipv4[.]ip_forward *= *1
report r1 says ~ inet 10[.]0[.]1[.]254/24
report m1 says ~ default via 10[.]0[.]1[.]254

# --- the experiment: the only proof of connectivity ---------------------------
reaches m1 m2
reaches m1 10.0.2.254

# --- and, after the exam session, that the machines were shut down properly ---
documents m1 has Terminal of
```

Note `journal r1 rc_config contains ip_forward`: it holds **here** because the scenario uses
`sysctl -w`, whose argument `set -x` does trace. Had it used a redirection, that same line would
fail on a correct machine — which is the whole point of § 4.2, and the reason the report
assertion sits right below it.

### 7.5 Playing it

```bash
export MARIONNET_CONTROL_SOCKET=/tmp/marionnet.sock
marionnet --control-socket "$MARIONNET_CONTROL_SOCKET" &
sleep 5

mrn-check lab.mrn && mrnctl -f lab.mrn
mrnctl rc-set r1 --from=/tmp/r1-scenario.sh --enable

mrnctl start-all
mrnctl wait-all --state=on --timeout=300
mrnctl wait r1 --ready --timeout=300          # the guest, not the process

mrnctl -q .content log r1 | grep '^!! FAILED' && echo "the scenario failed"
mrn-verify --json key.mrv > verdicts.json
jq -r '.assertions[] | "\(.verdict)\t\(.assertion)\t\(.reason // "")"' verdicts.json
```

### 7.6 Marking a student's copy of it

```bash
marionnet --control-socket /tmp/mark.sock /srv/exams/dupont.mar &
export MARIONNET_CONTROL_SOCKET=/tmp/mark.sock

mrnctl -q '.rows[].fields.Title' documents           # what the session archived
mrn-verify --refresh=never --json key.mrv > verdicts.json
mrnctl -q .content log m1 terminal | head -50        # what the student actually saw
```

Then write the mark sheet from `verdicts.json`, quoting for each `FAIL` the line of the terminal
recording that supports it. A `FAIL` you cannot support that way stays a remark.

---

## 8. Before you deliver — run this checklist

Do not report a lab as finished on the strength of having written it. Every line below is a
command whose output you must read.

1. `mrn-check lab.mrn` → *no error*. A `.mrn` that does not lint is not a lab.
2. `mrn-verify --check-only key.mrv` → *no error*; and offline against a grammar snapshot, read
   what it says it **could not answer**.
3. `mrnctl help <verb>` for every verb your scripts use — the vocabulary of *this* Marionnet, not
   your memory of it.
4. **Play the lab end to end at least once**, from `new` to the verdicts, and read the journals:
   `log <c> rc_config` for every component that has a scenario, `log <c> boot` for any guest that
   did not become ready.
5. Play the key against a **deliberately wrong** lab too (forwarding off, a cable missing). A key
   that passes on everything proves nothing — this is the single most common defect in a
   correction key.
6. Check that every `SKIP` in a clean run is one you accept. A key full of skips marks nothing.
7. `save-as` the `.mar`, quit, and **replay it** with `marionnet -r lab.mar`. The deliverable is
   the file, not the session you happened to have open.

When you report, say what you measured and what you did not, and quote the counts (assertions
passed / failed / skipped). "It should work" is not a result.

---

## 9. Where to look next

* `mrnctl help`, `mrn-check --help`, `mrn2sh --help`, `mrn-verify --help` — the authorities.
* `doc-src/scripting/README.md` — the guide to the channel: its shape, its invariants, its
  recipes, and the troubleshooting table.
* `doc-src/scripting/examples/` — runnable scripts, including an exam session and an assertion
  file.
* `doc-src/exam-mode.md` — what an exam session records, and what can be trusted in it.
* `docs/pilotage-par-script.md`, `docs/journalisation-profonde.md` — the design and the
  measurements behind all of the above (in French, developer audience).
