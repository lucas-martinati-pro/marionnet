# Runnable examples

The scripts of the guide (`../README.md`), as they are actually run.

They all expect a Marionnet already started in driven mode, and the socket in the
environment:

```bash
marionnet --control-socket /tmp/marionnet.sock &
export MARIONNET_CONTROL_SOCKET=/tmp/marionnet.sock
```

`mrnctl` is taken from `$PATH`, or from `useful-scripts/` of a source tree via `$MRNCTL`:

```bash
MRNCTL=../../../useful-scripts/mrnctl ./01-build-a-lab.sh
```

| File | What it shows |
|---|---|
| `01-build-a-lab.sh` | build a lab from nothing, address it, save it as a `.mar` |
| `02-run-and-collect.sh` | give a machine a scenario, start it, wait for the guest, read what it wrote |
| `scenario-ping.sh` | the guest side of `02` — bash the machine runs at the end of its boot |
| `03-router-daemons.sh` | configure the routing daemons of a router: write ZEBRA's file, leave one daemon out of the boot |
| `lab.mrn` | the same lab as `01`, in batch form (`mrnctl -f lab.mrn`), and the file `mrn-check lab.mrn` validates |

**On purpose, these scripts source no library** — not even the `bashbricks` vendored in this
repository, which is otherwise the rule for new scripts here. An example is meant to be copied
out of the source tree and edited; a dependency on the tree's layout would be the first thing
to break, and would hide behind helpers what the reader came to see. Same reasoning, and same
precedent, as `useful-scripts/marionnet-ctl`.
