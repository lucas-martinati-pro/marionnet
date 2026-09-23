#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory.
# Auto-login controller for guest virtual console (tty0).
# The AUTOLOGIN variable (1 or 0) is prepended dynamically by Simulation_level.make_hostfs_content.

: "${AUTOLOGIN:=1}"

if [[ "$AUTOLOGIN" -eq 1 ]]; then
  # -------------------------------------------------------------
  # 1. ENABLE AUTO-LOGIN
  # -------------------------------------------------------------
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

  # Systemd (Debian trixie / modern systems):
  if [[ -d /run/systemd/system ]] && type -p systemctl >/dev/null 2>&1; then
    mkdir -p /run/systemd/system/getty@tty0.service.d
    cat > /run/systemd/system/getty@tty0.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

else
  # -------------------------------------------------------------
  # 2. DISABLE AUTO-LOGIN: REVERT BACK TO NORMAL LOGIN PROMPT
  # -------------------------------------------------------------
  if [[ -f /etc/inittab ]]; then
    # BusyBox (Guignol): restore getty if /bin/login -f root was in place
    if grep -q "tty0::respawn:/bin/login" /etc/inittab; then
      sed -i -e 's|^tty0::respawn:/bin/login -f root.*|tty0::respawn:/sbin/getty -L  tty0 38400 vt100 # GENERIC_SERIAL|' /etc/inittab
      kill -HUP 1 2>/dev/null || true
      fuser -k -9 /dev/tty0 2>/dev/null || true
    fi
    if grep -q "^0:.*:respawn:/bin/login" /etc/inittab; then
      sed -i -e 's|^0:.*:respawn:/bin/login -f root.*|0:12345:respawn:/sbin/getty 38400 tty0|' /etc/inittab
      kill -HUP 1 2>/dev/null || true
      fuser -k -9 /dev/tty0 2>/dev/null || true
    fi
    # Debian SysV: remove --autologin root
    if grep -q "/sbin/getty --autologin root" /etc/inittab; then
      sed -i -e 's|/sbin/getty --autologin root|/sbin/getty|' /etc/inittab
      kill -HUP 1 2>/dev/null || true
      fuser -k -9 /dev/tty0 2>/dev/null || true
    fi
  fi

  # Systemd: remove autologin override and restart getty
  if [[ -d /run/systemd/system ]] && type -p systemctl >/dev/null 2>&1; then
    if [[ -f /run/systemd/system/getty@tty0.service.d/autologin.conf ]]; then
      rm -f /run/systemd/system/getty@tty0.service.d/autologin.conf
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl restart getty@tty0 2>/dev/null || true
    fi
  fi
fi
