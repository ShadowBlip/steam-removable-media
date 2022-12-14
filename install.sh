#!/bin/bash
set -e

echo "Installing Media Support Package"
cp -Rv usr/bin/shadowblip /usr/bin/
cp -Rv usr/bin/steamos-polkit-helpers /usr/bin/
cp -Rv usr/lib/hwsupport /usr/lib/
cp -Rv usr/lib/media-support /usr/lib/
cp -v usr/lib/systemd/system/media-mount@.service /usr/lib/systemd/system
cp -v usr/lib/udev/rules.d/10-media-mount.rules /usr/lib/udev/rules.d/
cp -v usr/lib/udev/rules.d/99-media-mount.rules /usr/lib/udev/rules.d/
cp -v usr/share/polkit-1/actions/org.shadowblip.media-support.policy /usr/share/polkit-1/actions

udevadm control -R
systemctl daemon-reload

exit 0
