# Teaching with Marionnet

*Preparing a lab, running the session, and marking it — with the control channel doing the
repetitive part. For the teacher who is willing to write a few lines of shell, or to have an
agent write them.*

This page is the **thread**: it goes from a statement given to students to a mark, and it says
which command does what at each step. It does not repeat what three other pages already say, and
it links to them at the exact place where you need them:

| Page | Read it for |
|---|---|
| `scripting/README.md` | the **shape** of the channel: how an answer is built, what `accepted` does not mean, the recipes, the batch mode, `mrn-check` / `mrn2sh` / `mrn-verify` |
| `exam-mode.md` | what an **exam session records**, where it ends up in the project, and what a mark may rest on |
| `lab-design-skill.md` | the procedure an **AI agent** must follow to design, play and grade a lab (§ 6 below is the teacher's side of that same page) |

Those names, and every relative path on this page, are relative to **the directory this file is
in**: `doc-src/` in the sources, `<prefix>/share/doc/marionnet/` on a machine where Marionnet is
installed. Run the shell examples of § 5 from there, or make the paths absolute.

---

## 1. Who this guide is for

You teach networking with Marionnet. You build a lab, you hand it out, students work in it, and
then you have thirty projects to look at. Everything in that sentence except the teaching is
repetitive, and all of it can be driven from a script:

* **building** a lab — components, cables, addresses, and what each guest runs at boot — instead
  of clicking it once per year and hoping the screenshot in the statement still matches;
* **checking** your own lab before you hand it out: a lab that has never been played is a
  hypothesis;
* **collecting** what a session did — inside the guests, not only around them;
* **marking**: a file of assertions replayed against every copy, which gives the same verdict for
  the same evidence, thirty times.

None of it replaces you. The channel can say *what is*; whether that is worth two points is
yours.

**What you need.** Marionnet itself, and the two clients that come with it: `mrnctl` (short form
of `marionnet-ctl`) and, for marking, `mrn-verify`. They need `socat` and `jq` on the host. If
you have never opened a driven session, read § 1 and § 2 of `scripting/README.md` first —
five minutes, end to end.

---

## 2. The workflow, and the file each step leaves behind

```
   design            build              hand out           session            mark
   ──────            ─────              ────────           ───────            ────
   statement    →    lab.mrn       →    lab.mar       →    student's     →    verdicts
   key.mrv           boot scenarios     (the project)      lab.mar            (PASS/FAIL/SKIP)
                                                           + up to 4
                                                             documents
                                                             per machine
```

| Step | What you write | What Marionnet leaves |
|---|---|---|
| **design** | the statement, and the assertions that will prove it (`key.mrv`) | — |
| **build** | a batch file `lab.mrn`, plus one shell script per component that has to be configured at boot | — |
| **hand out** | — | `lab.mar`, the project file: topology, addresses, boot scenarios, everything |
| **session** | — | the same `.mar`, plus — in exam mode — up to four documents per machine, inside the project (§ 5.5 says what makes it four) |
| **mark** | nothing new: the key you already wrote | one verdict per assertion, with the reason |

Two properties of that chain are worth stating once, because everything else follows from them:

* **the deliverable is the `.mar` file**, not the session you happen to have open. Whatever you
  build, save it, quit, and reopen it — `marionnet -r lab.mar`. A lab that has only ever existed
  in a running session has not been tested;
* **a script may do exactly what the GUI may do** — no more. A component that cannot be deleted
  while it runs cannot be deleted by the channel either. This is a contract, not a limitation to
  work around (§ 5 of the scripting guide).

---

## 3. Starting a driven session

```bash
marionnet --control-socket /tmp/lab.sock &
export MARIONNET_CONTROL_SOCKET=/tmp/lab.sock
```

The window opens as usual and stays usable: the channel does not replace the interface, it drives
the same session you are looking at. Everything below assumes those two lines.

For an exam, add `--exam` — it also turns on the two host-side recordings (`exam-mode.md`).
Be aware that an exam session **refuses** what would destroy the copy before it is archived: no
power cut (`poweroff`, `poweroff-all`, the *Power-off all* button), no `--no-save`, no `quit`
while something is still running, and no removal of a component which has already run — the last
one being liftable with `--exam-allow-delete` when you build the mock-up yourself. And the four
ways of leaving a project — Quit, the window's (x), Close, New, Open — no longer ask anything:
they shut every machine down, **wait until it is really down**, and save. See
`exam-mode.md` § 3.

---

## 4. One worked example per command

Every verb the channel publishes appears below exactly once, with one line you can run. The
sections follow the order of a real session — build, configure, start, observe, stop — and the
lines are meant to be played **in that order**: the last ones need what the first ones made.

> **Why this section may show commands when the scripting guide refuses to list them.** What
> follows is not a copy of the command list: it is a **session**, and it is replayed. Before this
> page is published, a bench opens a Marionnet, asks it for its vocabulary, and plays every line
> here against it (§ 9). A table copied out of `help` would be right the day it was written; a
> session that is replayed is either right or broken, never quietly stale. It still does not
> restate arities or option lists — for those, `mrnctl help <verb>`.

The two lines of § 3 are assumed. `mrnctl` is `marionnet-ctl` under its short name.

### 4.1 Session and vocabulary

```bash
mrnctl help                             # what this Marionnet understands — the authority
mrnctl help connect                     # the syntax of one verb
mrnctl status                           # is a project open, what is running, since when
mrnctl notifications                    # what the session did on its own since you last asked
```

### 4.2 The project

A project must exist before a component does: `add` on nothing answers `no_active_project`.

```bash
mrnctl new /tmp/teaching-demo.mar       # a new project, at that path
mrnctl save                             # write it where it belongs
mrnctl save-as /tmp/teaching-copy.mar   # …or somewhere else, and continue there
mrnctl close --save                     # close it, saving on the way out
mrnctl open /tmp/teaching-copy.mar      # reopen it — this is what a student's copy looks like
```

### 4.3 The model — components and cables

```bash
mrnctl add machine m1                   # a machine, with its default interface
mrnctl add machine r1 --ports=3         # three interfaces: eth0, eth1, eth2
mrnctl add switch sw1 --ports=8
mrnctl add hub h1 --ports=4
mrnctl connect c1 m1:eth0 sw1:port1     # a cable is created by connecting its two ends
mrnctl ls                               # every component, its kind and its state
mrnctl ls --kind=machine                # …of one kind only
mrnctl get m1                           # every field of one component
mrnctl get m1 memory                    # …or one of them
mrnctl set m1 memory 128                # one field at a time, always
mrnctl rename h1 h2
mrnctl can m1                           # what m1 accepts right now — ask, do not guess
mrnctl del h2                           # a component that may be deleted right now
```

The port names differ between kinds, and this is the first thing that trips a script: a machine
has `eth0…ethN`, a **`router` component has `port0…portN`**, a switch and a hub have
`port1…portN` (they count from 1). A refusal says which ones exist.

### 4.4 The four tables of the interface

These are the tabs of the interface, seen from a script — same content, same column names.

```bash
mrnctl ifconfig m1                                     # declared addresses, per interface
mrnctl ifconfig-set m1 eth0 ipv4-address 192.168.1.1/24
mrnctl defects m1                                      # the defects of a link, per direction
mrnctl defects-set m1 eth0 inward loss 5.0             # 5 % loss coming in
mrnctl documents                                       # what a session archived into the project
```

`ifconfig` holds what was **declared** in Marionnet — which the guest applies at boot — never
what a guest has configured for itself since. That distinction decides what a mark may rest on
(§ 5.4).

### 4.5 What a guest runs at boot

```bash
mrnctl rc-set m1 "printf 'ready\n' > /mnt/hostfs/marionnet-guest-ready"
mrnctl rc-get m1                        # what it will run, and whether that is enabled
```

The content runs as bash inside the guest at the end of its boot, and `/mnt/hostfs` is a real
host directory: whatever it writes there, the host can read without any network. The line above
is the smallest useful scenario — the "I am ready" marker of § 4.6. A real one comes from a file
(`--from=<absolute path>`, § 5.2).

The quotes are not decoration. The free tail of `rc-set` runs to the end of the line, but it is
still **your** shell that reads that line first: an unquoted `>` would redirect `mrnctl`'s own
output on the host instead of travelling to the guest. Same rule for a composite command given
to `exec` (§ 8).

### 4.6 Starting, and waiting for what actually happened

```bash
mrnctl start m1                         # accepted ≠ done: this only requests the transition
mrnctl wait m1 --state=on --timeout=120 # the process is running
mrnctl wait m1 --ready --timeout=300    # the GUEST says it is ready — see § 4.5
mrnctl start-all
mrnctl wait-all --state=on --timeout=300
```

`--state=on` says a process exists; `--ready` says the guest wrote the marker its scenario was
asked to write. Between the two there is a whole boot.

### 4.7 Observation — these need a running guest

```bash
mrnctl log m1                           # what its startup scenario did, with the status of each command
mrnctl log m1 boot --tail=5             # …or another of its journals, last five lines
mrnctl exec m1 -- uname -r              # run something INSIDE the guest, and get its status back
mrnctl report m1 --timeout=180          # a fresh snapshot of the guest's own state
mrnctl switch-info sw1                  # what a switch knows right now
mrnctl switch-info sw1 macs             # …one of its tables
```

Four verbs, three natures, and confusing them is how a wrong mark happens: `log` serves
**traces** (what was said, and by whom), `report` serves a **state** (what the guest is now),
`switch-info` serves the state of a *switch*, and `exec` is the only one that **acts**. A trace
does not show redirections; a report describes a state but never an accessibility. Only an
experiment — a ping run by `exec`, or `reaches` in a key — proves that something crosses.

### 4.8 Suspending, resuming, restarting

```bash
mrnctl suspend m1
mrnctl resume m1
mrnctl restart m1                           # a graceful shutdown followed by a start
mrnctl wait m1 --state=off                  # wait for shutdown
mrnctl wait m1 --state=on  --timeout=180    # wait for start
```

### 4.9 Stopping, and the states a machine leaves behind

```bash
mrnctl stop m1                          # the graceful shutdown — the one that archives, in exam mode
mrnctl wait m1 --state=off --timeout=180
mrnctl history m1                       # the saved states (cow files) of that machine
COW=$(mrnctl -q '.rows[0].children[0].fields."File name"' history m1)
mrnctl history-set "$COW" comment before the firewall
mrnctl history-start "$COW"             # start the machine from that state
mrnctl wait m1 --state=on --timeout=180
mrnctl history-del "$COW"               # forget one saved state
```

The name of a saved state is generated, so a script reads it rather than writing it down — which
is what the `-q` filter above does.

### 4.10 Leaving

```bash
mrnctl poweroff m1                      # the power cut: no shutdown sequence, nothing archived
mrnctl shutdown-all                     # every running component, gracefully
mrnctl poweroff-all
mrnctl save
mrnctl quit                             # closes Marionnet itself
```

`stop` and `poweroff` are not two ways of doing the same thing. In exam mode the four documents
of a machine are archived **by its graceful shutdown**; a power cut leaves nothing behind.

---

## 5. A complete lab, from statement to mark

One real lab, small enough to read on this page and complete enough to hand out: routing,
stateful filtering and source NAT. Everything below is versioned in
**`labs/session-7/`** and runs as it is.

```
   m1 ── h1 ── r1 ── h3 ── intruder
        LAN 1              "the outside"
     192.168.1.0/24        10.0.0.0/24
```

r1 is a **machine with three interfaces**, not a `router` component: the lab is about netfilter,
and the shipped router image runs Quagga without `iptables`. Nothing prevents a lab from using
the real router component — the point is that the choice belongs to the statement, not to habit.

### 5.1 The statement, in one paragraph

> The two ends are addressed and routed for you. On **r1**, which is not configured, make the LAN
> reach the outside, and nothing else: enable IPv4 forwarding, set the `FORWARD` policy to
> `DROP`, let the LAN out and let its answers back in, and make the LAN appear with r1's outside
> address. `intruder` must not be able to open anything towards the LAN on its own initiative.

### 5.2 Building it — `build.sh`

The topology is a batch file, `lab.mrn`, played in one call and checkable without sending
anything:

```bash
mrn-check labs/session-7/lab.mrn   # a .mrn that does not lint is not a lab
mrnctl -f labs/session-7/lab.mrn
```

The two ends then get a boot scenario — a file, this time, because it is more than one line:

```bash
mrnctl rc-set m1       --from=$PWD/labs/session-7/m1-scenario.sh       --enable
mrnctl rc-set intruder --from=$PWD/labs/session-7/intruder-scenario.sh --enable
mrnctl save-as /tmp/session-7.mar
```

`/tmp/session-7.mar` **is** the lab: hand out that one file. r1 has no scenario, and that
absence is the exercise.

### 5.3 Checking your own lab — `play.sh`

Play it once as a correct student would, by installing the solution as r1's scenario, and let
the key say whether it holds:

```bash
mrnctl rc-set r1 --from=$PWD/labs/session-7/r1-solution.sh --enable
mrnctl start-all
for c in m1 r1 intruder; do mrnctl wait $c --ready --timeout=300; done
mrn-verify labs/session-7/key.mrv
# 14 passed, 0 failed, 0 skipped.
```

Two details of `r1-solution.sh` are there for a reason, and both were found by measuring rather
than by reasoning:

* it writes `sysctl -w net.ipv4.ip_forward=1`, **not** `echo 1 > /proc/sys/…`. The journal of a
  scenario is a `set -x` trace, and a trace does not show redirections: the second form leaves
  the words `echo 1` and nothing else, so a *correct* machine would fail an assertion about its
  own configuration;
* it contains no `|| true`. A failure absorbed on the left of `||` never reaches the journal, and
  `journal r1 rc_config ok` would then pass on a scenario that did nothing.

### 5.4 The key — three kinds of evidence, and their order

`key.mrv` is a file of assertions, one per line, replayed identically against every copy. What
matters is not how many there are but what each one rests on:

| Kind | Example from the key | What it proves |
|---|---|---|
| the **model** | `cable c2 r1:eth0 h1:port2` | the topology of the statement is intact — a student may have moved a cable |
| the **trace** | `journal r1 rc_config ok` | the configuration ran and nothing in it failed. Never that the machine *is* in a given state |
| the **state** | `report r1 says ~ ip_forward *= *1` | what the guest says about itself now |
| the **experiment** | `reaches m1 intruder` | that something actually crosses. The only proof of connectivity |

A single run shows why the order matters. Switch the router's forwarding off from the outside,
in flight, and replay the very same key:

```bash
mrnctl exec r1 -- sysctl -w net.ipv4.ip_forward=0
mrn-verify labs/session-7/key.mrv
# 12 passed, 2 failed, 0 skipped.
```

Exactly two assertions flip, and they are the **state** (`report r1 says ~ ip_forward *= *1`) and
the **experiment** (`reaches m1 intruder`). `journal r1 rc_config ok` still **passes** — because
it is true: the configuration did run, an hour ago. A key made only of trace assertions marks a
machine that no longer works.

### 5.5 Marking thirty copies — `grade.sh`

An exam session is `marionnet --exam`: each machine shut down properly archives up to four documents
into the project itself (`exam-mode.md`). You then have two ways to mark, and they answer
different questions:

```bash
./grade.sh /srv/exams/dupont.mar recorded   # ask no guest anything: mark what the session left
./grade.sh /srv/exams/dupont.mar replay     # start the copy again and mark what it does
```

* **recorded** (`mrn-verify --refresh=never key-recorded.mrv`) reads the archived documents and
  the last report each guest wrote. Fast, and it is what thirty copies in one evening look like.
  It cannot judge connectivity: an accessibility is an experiment;
* **replay** starts the copy and plays the full key, `reaches` included. Slower, and the only way
  to see whether the lab actually works.

Three things to know before you trust either, all of them measured rather than assumed.

* **A copy whose machines were never shut down archives nothing.** The archiving is part of a
  graceful shutdown; a power cut skips it.
* **Ask each guest for a `report` before the session ends.** The shutdown hook writes one too,
  but only if it gets there: a machine stopped shortly after its boot has been seen to archive
  its console and its terminal and *no* report. `mrnctl report <c>` writes the file the archiving
  looks for, so one command per machine makes the archive complete — and it costs nothing to do
  it anyway.
* **`wait --ready` reports on a *running* guest.** On a component which is off — including one
  which has just been sent a `start`, since `start` answers before the startup is done — it
  waits instead of reading the marker the previous boot left. `grade.sh` goes one step further
  and waits for each guest to **answer** (`exec <c> -- true`), which also proves that `exec`,
  the verb the key uses next, works.

One last trap belongs to the marking, not to the session: the titles of archived documents are
**translated** — a French session files a report under *Rapport sur r1*. A key that greps for
`Report on` marks nothing on a colleague's machine. Write the alternative, as `key-recorded.mrv`
does; nothing in the channel is localised, but this treeview is.

---

## 6. Designing and grading a lab with an AI agent

Everything in § 5 is written work: a statement, a batch file, a scenario per component, a key.
It is exactly the kind of work an AI agent can draft — and exactly the kind where a draft that
*looks* right is dangerous, because a lab that does not run wastes a room full of students, and a
key that passes on everything marks nothing.

Marionnet therefore ships the procedure the agent is supposed to follow:
**`lab-design-skill.md`**. It is not documentation about the agent, it is the agent's
instructions — what exists in the channel, what counts as evidence, what a verdict may rest on,
and a checklist it must run before reporting. Hand it over explicitly:

> Read `lab-design-skill.md` and follow it. Then: *(your lab, in your words)*.

In Claude Code this repository also carries it as a skill (`marionnet-lab-design`), which is
loaded by naming it; the content is the same page.

### 6.1 What to give the agent

Four things, and they are the four the agent cannot invent:

1. **the pedagogical intent** — what the student must *understand*, not what they must type
   ("subnetting and a default route", "stateful filtering and SNAT");
2. **the constraints of your room** — how long the session lasts, how many machines a laptop can
   hold, which guest images are installed here (`marionnet` lists them in the machine dialog; a
   lab that names an image nobody has is a lab nobody can play);
3. **what the student produces** — a configuration written by hand? a script? answers on paper?
   This decides what the key can look for;
4. **whether it will be graded**, and on what evidence. Say it up front: it changes the design,
   not the wording (§ 6.3).

### 6.2 What to demand before you believe it

The skill ends with a seven-point checklist; your job is to require its **output**, not its
promise. Ask for these four things and read them:

| Demand | Why |
|---|---|
| the **counters** of a full run — assertions passed / failed / skipped | "it should work" is not a result. A key nobody has played is a hypothesis |
| the key played against a **deliberately wrong** lab (forwarding off, a cable missing) | a key that passes on everything proves nothing. This is the single most common defect in a correction key |
| the list of **`SKIP`**s in a clean run | a `SKIP` is "the channel has no way to know". One you did not intend is a hole in the marking |
| the `.mar` **saved, quit and replayed** (`marionnet -r lab.mar`) | the deliverable is the file, not the session the agent had open |

If the agent reports a lab as finished without those, it has reported the writing, not the lab.

### 6.3 Two different jobs

**(a) An ordinary lab.** The agent drafts the statement, `lab.mrn`, the boot scenarios and a key;
you play it once yourself — it costs five minutes — and you read the journals of every component
that has a scenario (§ 4.8). What you keep is the `.mar`, and what you hand out is that same
file. The key is your own safety net: it tells you next year whether the lab still runs, on a
Marionnet that has moved.

**(b) A graded exam.** Three things change:

* the session is started with `--exam`, so every machine that is shut down properly archives up
  to four documents into the project (`exam-mode.md`);
* the key is written against **what the host wrote**, not against what a guest says about itself.
  A report and a history are written *inside* the guest, in a directory the student can write to.
  The console and the terminal recording are written by Marionnet. A `FAIL` whose only evidence is
  guest-written is a *finding*: quote the terminal recording next to it, or lower the claim;
* the marking is replayed identically on thirty copies, which is the whole point — but the
  **marking scheme is yours**. The channel says whether a route exists; whether its absence costs two
  points or four is a pedagogical decision, and no agent should be asked to make it.

### 6.4 What not to delegate

The statement's *ambiguities* (an agent will resolve them silently, students will not), the
marking scheme, and the decision to sanction. Everything else — building, replaying, collecting,
verdicts — is repetitive, and repetitive is what this channel is for.

---

## 7. After the session

What survives a session, and for how long:

| Thing | Where it lives | How long |
|---|---|---|
| the lab itself | the `.mar` file | forever — it is the deliverable |
| the exam documents (up to four per machine) | inside the same `.mar`, Documents tab | forever, **if** the machine was shut down properly |
| the journals (`rc_config`, `boot`, `console`, `terminal`, `commands`, `report`, `exec`) | the project directory, readable with `log` | as long as the project is open |
| a rendered report page | nowhere — it is **served** on `127.0.0.1` for a couple of minutes | reloading the tab later fails; ask for the document again |

Two consequences for a teacher:

* **collect before you close.** A project closed with machines still running archives nothing:
  the archiving is part of a graceful shutdown. If a student's machine is stuck, you keep the
  console and the terminal (host-written, always there) but not the report;
* **what the channel ran is not the student's work.** Commands injected with `exec` go to a
  journal of their own and are deliberately *not* archived into the project: a corrector's probes
  never land in the student's history.

---

## 8. Limits you will meet

Every line below has cost somebody a debugging session. The full table is § 6 of
`lab-design-skill.md`; these are the four that bite a teacher first.

| What happens | What to do |
|---|---|
| A machine that was never shut down leaves **no documents** in the project | shut down before collecting; `wait <c> --state=off`, then wait for the row to appear in `documents` — archiving is the *last* thing a shutdown does |
| An old SysV guest image (the shipped router image is one) produces **no report at shutdown** | ask for it **while the guest runs**: `report <c>`. It is written where the shutdown hook would have written it, so it is archived like any other |
| A `rc-set` on a **switch** is only taken into account at its **first** start; a later one is accepted, `rc-get` shows the new text, and the next start replays the old | a lab that needs two switch configurations uses **two switches** |
| `wait <c> --ready` waits, and finally refuses with *is "off", not "on"* | `start` answers before the startup is done: the component was not running yet, or never came up. Check `wait <c> --state=on` first — or wait for the guest to *answer*: `exec <c> -- true` |

Two more, about reading answers rather than running things: a journal answer is capped at 400
lines (`--tail=` moves the window, and `truncated` tells you there was more), and an `exec` output
at 200 — an output is a value, not a document. If you need a document, have the guest write a
file and read the journal.

---

## 9. How this guide stays true

The § 4 examples are not a copy of the command list: **they are commands, and they are replayed**.
Before this page is published, a bench opens a real session, asks it for its vocabulary, plays
every line of § 4 against it, and checks the correspondence **in both directions** — every verb
the server publishes has an example here, and no example names a verb the server does not
publish. A verb added to Marionnet breaks that bench until it is documented here; an option
renamed makes its example fail.

What this page still does **not** do is restate arities and option lists. Those live in the
server and are served by `help`, which is the authority — here as in the scripting guide. When in
doubt:

```bash
mrnctl help <verb>
```
