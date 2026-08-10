# Project files are now text — format `v3`

*Release note for teachers who keep a collection of `.mar` lab projects.*

A Marionnet project (`.mar`) is a gzipped archive holding the description of your virtual
network. Until now the files inside it were **OCaml binary dumps**: unreadable outside
Marionnet, undiffable, and silently fragile — a change in the program could make an old project
unreadable with no warning. From this version on, everything Marionnet writes to describe your
network is **text**: JSON for the description files, plain scripts for the startup scripts.

Nothing changes in how you use Marionnet. This note is about your **existing** projects, and
about one thing you should know before saving them with the new version.

---

## 1. What changed

* A saved project is now text. You can read it, `grep` it, `diff` it, and keep it under version
  control — a lab that changed by one address shows up as one changed line.
* A project you did not modify is now rewritten **identically**. Until this version the order of
  the components flipped at every save/reload cycle, which made any comparison useless. (One
  file still changes at every save: `states/ifconfig-counters.json` carries an obsolete field
  drawn at random. It is the only one.)
* Nothing about the interface, the machines, or the way you work changes.

## 2. What did not change

Your old projects still open. Marionnet reads every format it has ever written (`v0`, `v1`,
`v2`), converts what needs converting when you open an old lab, and keeps doing it exactly as
before. The archive is still a `.mar` you can copy, mail and archive as usual.

## 3. Before you save: this is a one-way door

Opening an old project changes nothing on disk. **Saving** it does: the project is then written
in the new format, and **an older Marionnet will not be able to open it again**.

Marionnet says so when it opens such a project — the warning is not new, it is the one it has
always shown when a project was about to change format:

> **Project in old file format** — This project will be automatically converted in a format not
> compatible with previous versions of this software. If you want to preserve compatibility,
> don't save it or save it with another name.

That case has been measured, not guessed. Put in front of a `v3` project, an older Marionnet:

* refuses to open it and says so (`Failed loading the project`);
* stays alive — no crash, and no half-loaded lab on screen;
* leaves the file **intact**: a refusal never damages a project.

So the failure is clean, but it is a failure. If some of your machines still run an older
Marionnet — a lab room not updated yet, a colleague, a virtual machine you keep for a course —
**keep a copy of the `.mar` before saving it with the new version**:

```bash
cp lab.mar lab-v2-backup.mar
```

There is no downgrade: a `v3` project cannot be turned back into an old one.

## 4. Telling which format a project is in

The version is a small file inside the archive:

```bash
$ tar xzf lab.mar -O --wildcards '*/version'; echo
v2
```

(the file holds the tag and nothing else, not even a newline — hence the `echo`)

`v0`, `v1`, `v2` are the old binary formats; `v3` is the text one. The same command over a
project saved by this version answers `v3`.

## 5. Converting a set of projects

There is no separate conversion tool, on purpose: the only program that may write a Marionnet
project is Marionnet itself. Converting is therefore *opening and saving*, which the control
channel can do without anyone clicking (see `doc-src/scripting/README.md` for the channel
itself):

```bash
export MARIONNET_CONTROL_SOCKET=/tmp/marionnet.sock
marionnet --control-socket "$MARIONNET_CONTROL_SOCKET" &
sleep 5

for f in ~/labs/*.mar; do
  cp "$f" "$f.backup"                      # see § 3 — do this first
  mrnctl open "$f" --timeout=120
  mrnctl save --timeout=120
  mrnctl close --no-save --timeout=120
done

mrnctl quit
```

Two remarks about that loop:

* opening an old project may **adapt** it (an obsolete kernel replaced by a supported one, for
  instance); `mrnctl open` reports those adaptations in its answer, and they are part of what
  gets saved;
* `--timeout=120` is not decoration. A request that does not carry one is bounded to **5
  seconds** by the server, and a save can exceed that on a large project or a busy machine — you
  would then be told an operation failed when it was merely slow.

## 6. Where the data lives now

| Inside the `.mar` | What it holds |
|---|---|
| `version` | the format tag (`v3`) |
| `netmodel/network.json` | the network itself: machines, routers, switches, cables |
| `netmodel/dotoptions.json` | the drawing (layout, zoom, which cables are flipped) |
| `states/ifconfig.json` | addresses, one row per network card |
| `states/ifconfig-counters.json` | the counters used to hand out the next address |
| `states/defects.json` | the simulated defects (loss, delay, duplication) |
| `states/states-forest.json` | the disk states of the machines |
| `states/texts.json` | the documents attached to the project |
| `states/rc_config.*` | the startup scripts, one file per component that has one |

The startup scripts are plain files rather than a field inside the network description: a
script is a script, and it belongs in a file you can open.

## 7. Where to read more

* Driving Marionnet from a script: `doc-src/scripting/README.md`.
* The design of the format and the reasons behind it (French, for developers):
  `docs/migration-marshal-to-text.md`.
