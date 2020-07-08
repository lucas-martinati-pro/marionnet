#!/bin/bash

set -e

FILES+=" etc/init.d/marionnet-relay"
FILES+=" etc/init.d/marionnet-dummy-xserver"
FILES+=" usr/bin/marionnet-dummy-xservice"

TARNAME="marionnet-guest-stuff"

TMPDIR=$(mktemp -d $TARNAME.XXXXXX)
cd $TMPDIR

for i in $FILES; do
  mkdir -p $(dirname $i)
  [[ -f ../$(basename $i) ]] && cp ../$(basename $i) $(dirname $i)/
done

TARGET=../$TARNAME.$(date +%Y-%m-%d.%H\h%M | tr -d " ").tgz
tar cvzf $TARGET */

set +e
# ---
for i in $(find $(find /tmp/marionnet-*.dir -type d -name hostfs) -name GUESTNAME); do
  echo "---"
  D=${i%%/GUESTNAME};
  echo -n "Do you want to copy the tarball in $D (y/..) ? "; read A
  if [[ $A = y ]]; then
    cp $TARGET $D/
  fi
done
# ---

cd ..

echo "---"
du -sh ${TARGET#../}
echo "---"

echo "This tarball may be installed in a virtual machine with the following actions"
echo "(to be performed in the UML terminal as \"root\"):"
echo "---"
echo "  cd /"
echo "  tar xvzf /mnt/hostfs/${TARGET#../}"
echo "  chown root:root $FILES"
echo "  systemctl enable marionnet-relay"
echo "  systemctl enable marionnet-dummy-xserver"
echo "  # or for old System-V based machines:"
echo '  # for i in $(find /etc/rc?.d/ -name "*marionnet-relay"); do ln -s ../init.d/marionnet-dummy-xserver ${i%S*marionnet-relay}/S20marionnet-dummy-xserver; done'
echo "  # update-rc.d marionnet-dummy-xserver enable"
echo "  # reboot"
echo "---"

# Mr proper:
rm -rf "$TMPDIR"

