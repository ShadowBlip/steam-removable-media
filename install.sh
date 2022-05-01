#!/bin/bash
set -e

echo "Installing Media Support Package"
cp -Rv media-support /usr/lib/
cp -v 99-media-mount.rules /etc/udev/rules.d/
cp -v "media-mount@.service" /etc/systemd/system/
udevadm control --reoad-rules
systemctl daemon-reload

exit 0
