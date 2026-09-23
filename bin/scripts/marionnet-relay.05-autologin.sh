#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory.
# Auto-login as root on virtual console (tty0).

# 1. BusyBox (Guignol machines & routers) & SysV init:
if [[ -f /etc/inittab ]]; then
  if grep -q "getty.*tty0" /etc/inittab; then
    if grep -q "GENERIC_SERIAL" /etc/inittab || [[ -L /sbin/getty && $(readlink /sbin/getty) == *busybox* ]] || type -p busybox >/dev/null 2>&1; then
      # Busybox init: launch /bin/login -f root directly on tty0 without prompt
      sed -i -e 's|^tty0::respawn:.*getty.*|tty0::respawn:/bin/login -f root|' /etc/inittab
      sed -i -e 's|^0:.*getty.*tty0.*|0:12345:respawn:/bin/login -f root|' /etc/inittab
    else
      # Debian SysV agetty: pass --autologin root
      sed -i -e 's|/sbin/getty -L|/sbin/getty --autologin root -L|' /etc/inittab
      sed -i -e 's|/sbin/getty 38400|/sbin/getty --autologin root 38400|' /etc/inittab
    fi
    kill -HUP 1 2>/dev/null || true
  fi
fi

# 2. Systemd (Debian trixie / modern systems):
if [[ -d /run/systemd/system ]] && type -p systemctl >/dev/null 2>&1; then
  mkdir -p /run/systemd/system/getty@tty0.service.d
  cat > /run/systemd/system/getty@tty0.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
fi
