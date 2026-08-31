# Session 7 — routing, filtering, source NAT

A complete lab: a statement, the project handed out to the students, a solution, and a
correction key played against a live session. It is the worked example of
`teacher-guide.md` § 5, and it runs as it is.

```
   m1 ── h1 ── r1 ── h3 ── intruder
        LAN 1              "the outside"
     192.168.1.0/24        10.0.0.0/24
```

`r1` is a **machine with three interfaces**, not a `router` component: this lab is about
netfilter, and the shipped router image runs Quagga without `iptables`.

## The statement

> The two ends are addressed and routed for you. On **r1**, which is not configured, make the LAN
> reach the outside, and nothing else: enable IPv4 forwarding, set the `FORWARD` policy to
> `DROP`, let the LAN out and let its answers back in, and make the LAN appear with r1's outside
> address. `intruder` must not be able to open anything towards the LAN on its own initiative.

## The files

| File | What it is |
|---|---|
| `lab.mrn` | the topology and the declared addresses, in batch form (`mrn-check lab.mrn` validates it) |
| `m1-scenario.sh`, `intruder-scenario.sh` | what the two ends run at boot: their default route, and the marker `wait --ready` waits for |
| `r1-solution.sh` | the solution, as r1's boot scenario. **Not** handed out |
| `key.mrv` | the correction key, against a **running** lab: model, trace, state, experiment |
| `key-recorded.mrv` | the key for a copy that is over: the archived documents and the last report each guest wrote |
| `build.sh` | builds the project to hand out (r1 left unconfigured) and saves it |
| `play.sh` | plays it as a correct student would, marks it, then switches forwarding off and marks it again |
| `grade.sh` | marks one student's copy, `replay` or `recorded` |

## Using it

```bash
marionnet --control-socket /tmp/lab.sock &
export MARIONNET_CONTROL_SOCKET=/tmp/lab.sock

./build.sh /tmp/session-7.mar     # hand this file out
./play.sh                         # what a teacher owes their own lab before handing it out
./grade.sh /srv/exams/dupont.mar recorded
```

`mrnctl` and `mrn-verify` are taken from `$PATH`; from a source tree, point at them with
`MRNCTL=` and `MRN_VERIFY=`.

Like the scripts of `scripting/examples/`, and for the same reason, **these source no
library** — not even the `bashbricks` vendored in this repository. A lab is meant to be copied
out of the source tree and edited into next year's lab; a dependency on this tree's layout would
be the first thing to break.
