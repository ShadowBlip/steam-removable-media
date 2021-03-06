#!/bin/bash
set -e

echo "Removing Media Support Package"
rm -rfv "/usr/lib/media-support"
rm -v "/etc/udev/rules.d/99-media-mount.rules"
rm -v "/etc/systemd/system/media-mount@.service" 
rm -v "/etc/removable-libraries"
udevadm control -R
systemctl daemon-reload

exit 0
