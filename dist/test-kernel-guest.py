#!/usr/bin/env python3
"""Run inside kernel-release-test.Dockerfile with SYS_PTRACE and no seccomp.

Boot a read-only guest image with a disposable COW, log in, and exercise the
kernel ABI used by legacy iptables. pexpect controls only this test's process.
"""
import argparse
import os
from pathlib import Path
import tempfile

import pexpect


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image")
parser.add_argument("--kernel", default="/usr/share/marionnet/kernels/linux-6.12.95-i386")
parser.add_argument("--log", required=True)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="uml-netfilter-") as work, open(args.log, "w") as log:
    cow = Path(work) / "guest.cow"
    child = pexpect.spawn(args.kernel, [
        f"ubda={cow},{args.image}", "root=98:0", "rw", "rootflags=errors=continue",
        "mem=256M", "con=none", "con0=fd:0,fd:1", "ssl=none", "hostname=netfilter-test",
        f"umid=netfilter-{Path(args.image).name}",
    ], encoding="utf-8", timeout=90, env=dict(os.environ, TMPDIR=work))
    child.logfile_read = log
    try:
        child.expect("login:")
        child.sendline("root")
        prompt = r"(?m)^[^\r\n]*root@[^\r\n]*[#$] ?"
        choice = child.expect(["Password:", prompt])
        if choice == 0:
            child.sendline("root")
            child.expect(prompt)
        command = (
            "(set -e; uname -rm; iptables -L -n; iptables -t nat -L -n; "
            "ip6tables -L -n; ip6tables -t nat -L -n; "
            "iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT; "
            "iptables -A INPUT -p tcp -m multiport --dports 22,80 -j ACCEPT; "
            "iptables -A INPUT -p icmp -j LOG; "
            "iptables -A INPUT -p tcp --dport 1 -j REJECT; "
            "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; "
            "iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.0.0.2:80; "
            "iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -j SNAT --to-source 192.0.2.1; "
            "iptables-save); result=$?; printf '\\nNETFILTER_TEST_STATUS_%s\\n' \"$result\""
        )
        child.sendline(command)
        child.expect(r"(?m)^NETFILTER_TEST_STATUS_([0-9]+)\r?$")
        assert child.match.group(1) == "0", f"guest firewall test failed: {child.match.group(1)}"
        child.sendline("/sbin/poweroff -f")
        child.expect(pexpect.EOF, timeout=30)
        child.close()
        assert child.exitstatus == 0, f"UML exit status {child.exitstatus}"
        print(f"PASS: {args.image}: boot, IPv4/IPv6 filter/NAT, matches and targets, shutdown")
    finally:
        if child.isalive():
            child.terminate(force=True)
