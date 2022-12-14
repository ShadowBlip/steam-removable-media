#!/bin/bash
set -e

echo "removing Media Support Package"
rm -rfv /usr/bin/shadowblip
rm -rfv /usr/lib/hwsupport
rm -rfv /usr/lib/media-support
rm -v /usr/lib/systemd/system/media-mount@.service
rm -v /usr/lib/udev/rules.d/10-media-mount.rules
rm -v /usr/lib/udev/rules.d/99-media-mount.rules
rm -v /usr/share/polkit-1/actions/org.shadowblip.media-suppurt.policy
rm -v /usr/share/polkit-1/rules.d/org.shadowblip.media-support.rules

udevadm control -R
systemctl daemon-reload

exit 0
