# The exam mode

*What a Marionnet session records when it is started for an exam, where it ends up, and what
can be trusted in it — for the teacher, with or without the control channel.*

```bash
marionnet --exam
```

The window says `Marionnet (EXAM)`, the launcher icon is the exam one, and the flag `exam=1`
is passed to every guest that boots. What this page is about is the rest: since 2026 an exam
session **records itself**, and a machine which is shut down properly leaves what it did inside
the project file.

---

## 1. What is recorded

Four documents per virtual machine or router, of two different origins:

| Document | Written by | What it is |
|---|---|---|
| **Report** | the guest, at shutdown | a Markdown snapshot of the machine's final state: interfaces, link layer, routing tables (IPv4 and IPv6), ARP neighbours, forwarding, name resolution, persistent configuration, **firewall** (`iptables` filter/nat/mangle, a replayable form, `ip6tables`, `nftables`), listening sockets, failed services, processes and mounts |
| **History** | the guest, at every prompt | every command typed, each one preceded by its date — written as it happens, not collected at the end |
| **Console** | Marionnet, host side | the console of the virtual machine's process: what its kernel and its init said, from the very first line |
| **Terminal** | Marionnet, host side | the recorded terminal session — the commands **and their output**, as the student saw them |

Nothing has to be installed in the guest images: Marionnet deposits what it needs into each
machine's shared directory at every boot. Old images work as they are.

Each section of the report holds the raw output of the command that produced it, inside a code
block. A guest which does not have a given command — a minimal image without `ip` or without
`iptables` — produces a report that **says so**, rather than an empty section.

## 2. Where it ends up

At the **graceful shutdown** of a machine (the *Shutdown* gesture, not a power cut), the four
documents are archived into the **Documents** tab, under the titles *Report on …*, *History
of …*, *Console of …* and *Terminal of …*. From there they are part of the project: saving the
`.mar` file saves them, and opening that file elsewhere brings them back.

Two consequences worth knowing:

* **a machine which is not shut down leaves nothing** in the project: a power cut skips the
  archiving entirely. This is exactly what the exam mode now refuses to let happen — see § 3;
* the archiving is the **last** thing a shutdown does, so on a slow guest it lands a moment
  after the machine's icon has gone grey.

A document is opened by double-clicking it, as any imported document. Reports are Markdown, and
they open **rendered**, in the browser Marionnet is configured to use (`MARIONNET_HTML_READER`,
`xdg-open` by default). Their **source** is one gesture away: right-click the document and choose
*Show the source*, which opens it in a syntax-coloured window.

Whether that window lets you **write** depends on who is in front of it, and this is deliberate:

* **during the exam** — Marionnet started with `--exam` — the source is **read-only**. The
  student can read what their session produced; they cannot rewrite their own copy from the
  interface;
* **afterwards**, when the teacher (or a script, or an agent) reopens the same project **without**
  `--exam`, the very same gesture opens an editor: annotating a report is then one of the reasons
  the archive exists, and `OK` writes it back into the project.

Three things are worth knowing about that rendering, because they concern a document on which a
mark may rest:

* the conversion is done **by Marionnet itself**, not by a converter of the host. The page is
  therefore **the same everywhere** — the same on the student's machine, on yours, and on the
  machine of whoever opens the archive later. It is not written anywhere either: Marionnet
  **serves** it on `127.0.0.1`, under an unguessable address, for the couple of minutes a browser
  needs to fetch it, then stops. This is what makes it work with a browser installed as a snap or
  a flatpak — those are confined and would not see a file left in `/tmp` — and it leaves nothing
  behind. The counterpart: reloading that tab much later gives an error, ask for the document
  again;
* the report is written **inside the guest**, so on a machine the student controls. Any raw HTML
  it may contain is **not** given to the browser: it is dropped, and the page says so in its
  place, in red. Nothing written in a report can run in the page you read. What was dropped
  remains visible in the source;
* should you prefer another converter (a richer rendering, say `pandoc`), set
  `MARIONNET_MARKDOWN_TO_HTML` in `marionnet.conf` or in the environment: it receives the
  Markdown on its standard input. This gives up the two properties above; Marionnet falls back on
  its own conversion if that command is missing, fails, or answers nothing.

## 3. What the exam mode refuses (and why)

Everything above hangs on **one** gesture: the graceful shutdown is where a session is archived
into the project. Every other way of stopping a guest throws that copy away — and the most
tempting of them, *Power-off all*, sits right next to *Shutdown all* in the bottom toolbar. In an
exam session, those ways are therefore closed:

| Gesture | Outside an exam | With `--exam` |
|---|---|---|
| *Power-off all* button, `poweroff`, `poweroff-all` | available | **refused**: the button is greyed out and says why; the channel answers `forbidden_in_exam_mode` |
| **Quit**, the window's **(x)**, **Close**, **New**, **Open** — the four ways of leaving a project | ask whether to save | **do not ask**: they shut every machine down gracefully, **wait for it**, and save. There is no wrong button to press |
| `quit` through the control channel | quits at once | **refused** while something is running or the project has unsaved changes (`close --save` first, then quit) |
| `close --no-save`, `new … --no-save`, `open … --no-save` | available | **refused**: an archive that never reaches the `.mar` is an archive nobody will read |
| Removing a component (*Remove*, `del`) | available | **refused for a component which has already run** — removing it would take its disk states, its shared directory and its journals along |

**« Wait for it » is the whole point of that second line.** The archiving is the *last* thing a
graceful shutdown does, and shutting down is asynchronous: saving right after asking for it wrote a
project file without the very documents the save was for. In an exam session the four gestures now
shut down, **wait until every machine is really down**, and only then save — so leaving may take a
few seconds longer than it used to, and what you get is a complete copy.

The last line deserves its nuance: a component which was **never started** stays removable. It has
produced nothing, and a student building their own topology must be able to undo a mistake. Only
what has run is protected. If you would rather keep the plain behaviour — say, you prepare the
mock-up yourself in an exam session — start Marionnet with:

```bash
marionnet --exam --exam-allow-delete
```

The **Options** menu carries a witness of that lock (checked, greyed out, and absent outside an
exam mode): it is there so that a student who finds an empty *Remove* submenu understands that the
tool is refusing, rather than believing the interface is broken.

Nothing of this changes the vocabulary of the control channel: the commands are still the same,
still listed by `help`. What changes is what a component *can* do — `can <component>` stops
publishing the refused actions — and `status` says `"exam": true`, which is how a script learns
the mode instead of guessing it from a refusal.

**Outside an exam**, none of this applies: throwing an experiment away is a legitimate gesture, and
often the point of a rehearsal. The question is still asked — but it now says what would be lost
when something has run in the session: the disk states of the components, and every document
already archived into the project.

## 4. What can be trusted

The report and the history are written **by the guest**, into a directory the student can
write to. A student who knows this can edit them, and a mark cannot rest on them alone.

The console and the terminal recording are written **by Marionnet, on the host**: nothing
inside the virtual machine can reach them, and the terminal recording holds the commands
together with their output. That is the piece of evidence a mark can rest on — and the reason
the exam mode records the terminal at all.

One journal is neither the student's nor evidence about them: `exec` holds what **the channel**
was made to run inside a guest — by you, or by a script correcting the lab. It is kept in a file
of its own precisely so that it never lands in the student's history, and it is **not** archived
into the project: what a corrector injected is not the work being marked. It is read while the
session is alive, with `marionnet-ctl log <machine> exec`.

## 5. Limits, measured rather than assumed

* **Old SysV guest images have no shutdown sequence** (their `inittab` answers Marionnet's
  shutdown gesture by halting immediately), so they produce **no report at shutdown**. Their
  history, console and terminal are unaffected — the first is written continuously, the two
  others by the host. The remedy costs one command: ask the guest for a report **while it is
  still running** (`marionnet-ctl report <machine>`). That report is written to the same place
  the shutdown hook would have written it, so the archiving finds it and files it under
  *Report on …* like any other.
* **Routers** are treated exactly like machines, and this is now measured end to end: a router
  archives its report, its history, its console and its terminal. The image currently shipped is
  a 2014 busybox one, hence one of the SysV cases above — so the report of a router is the one
  you ask for before shutting it down.
* The report is deliberately **sober**: it is a dependency-free replacement for a producer that
  died years ago, not a system-audit tool.

## 6. Without the exam mode

The two host-side recordings can be switched on separately, for a demonstration or a bug
hunt:

```bash
marionnet --console-log        # record each machine's console
marionnet --terminal-log       # record each machine's terminal session
```

They are what `--exam` turns on for you; what `--exam` adds is the archiving into the project.

Everything above can also be read **while the session is running**, without waiting for a
shutdown and without opening a window, through Marionnet's control channel: see
`doc-src/scripting/README.md`, § 11. That is how a lab is checked by a script — or by an agent
— rather than by hand.

If what you want is the whole thread — preparing a lab, handing it out, running the session and
marking the copies, with one worked example per command — that is `doc-src/teacher-guide.md`,
and a complete lab lives in `doc-src/labs/session-7/`.

And if the marking itself is what you want delegated: `doc-src/lab-design-skill.md` is the
procedure an AI agent should follow to design a lab, write its correction key as a file of
assertions, and grade a session from it — including which of the four documents above a mark may
rest on, and which it may not.
