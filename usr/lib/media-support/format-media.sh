#!/bin/bash
# Modified from SteamOS 3 format-sdcard.sh

set -e

# Verify root user.
if [ "$EUID" -ne 0 ]
  then echo "Must be run as root. Exiting..."
  exit 0
fi

# Verify correct usage.
usage()
{
  echo "Usage: $0 device_name (e.g. sdb)"
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

DEVICE=$1
DEVICE_FULL="/dev/$DEVICE"
MOUNT_LOCK="/var/run/media-mount.lock"
RUN_VALIDATION=1

# Verify device exists and start format..
if [[ ! -e $DEVICE_FULL ]]; then
  echo "$DEVICE not found. Aborting..."
  exit 19
fi

# mmc and nvme devices use p as prefix for the partition number.
if [[ $DEVICE =~ mmcblk[0-9] || $DEVICE =~ nvme[0-9]n[0-9] ]]; then
	PART=${DEVICE}p1
else
	PART=${DEVICE}1
fi
PART_FULL="/dev/$PART"


# lock file prevents the mount service from re-mounting as it gets triggered by udev rules
on_exit() { rm -f -- "$MOUNT_LOCK"; }
trap on_exit EXIT
echo $$ > "$MOUNT_LOCK"

if [[ "$RUN_VALIDATION" != "0" ]]; then
    echo "stage=testing"
    if ! f3probe --destructive "$DEVICE_FULL"; then
        # Fake sdcards tend to only behave correctly when formatted as exfat
        # The tricks they try to pull fall apart with any other filesystem and
        # it renders the card unusuable.
        #
        # Here we restore the card to exfat so that it can be used with other devices.
        # It won't be usable with the deck, and usage of the card will most likely
        # result in data loss. We return a special error code so we can surface
        # a specific error to the user.
        echo "stage=rescuing"
        echo "Bad sdcard - rescuing"
        for i in {1..3}; do # Give this a couple of tries since it fails sometimes
            echo "Create partition table: $i"
            dd if=/dev/zero of="$DEVICE_FULL" bs=512 count=1024 # see comment in similar statement below
            if ! parted --script "$DEVICE_FULL" mklabel msdos mkpart primary 0% 100% ; then
                echo "Failed to create partition table: $i"
                continue # try again
            fi

            echo "Create exfat filesystem: $i"
            sync
            if ! mkfs.exfat "${PART_FULL}"; then
                echo "Failed to exfat filesystem: $i"
                continue # try again
            fi

            echo "Successfully restored device"
            break
        done

        # Return a specific error code so the UI can warn the user about this bad device
        exit 14 # EFAULT
    fi
fi

# User verify erase disk.
read -n 1 -p "This will completely erase the entire disk $DEVICE. Are you sure? [Y/n]" response
case "$response" in [Nn])
  printf "\nNo received. Aborting..."
  exit 0
  ;;&
  *)
  printf "\n"
esac

# Stop the service to remove the drive from steam.
systemctl stop media-mount@${PART}.service || echo "Mount service not running. Continuing..."

# Unmount any existing partitions.
MOUNT=$(df -h | grep $DEVICE | awk '{print $6}')
if [ ! -z "$MOUNT" ]; then
  for MNT_PART in $MOUNT
  do
    for FSTAB_MNT in $(cat /etc/fstab | awk '{ print $2 }')
    do
      if [ "$MNT_PART" = "$FSTAB_MNT" ]; then
        echo "$DEVICE is mounted on $MNT_PART and is part of /etc/fstab. Aborting..."
        exit 1
      fi
    done
    if ! umount $MNT_PART > /dev/null; then
      echo "Failed to unmount $MNT_PART."
      exit 1
    fi
  done
fi

# Create the new filesystem.
sync
parted --script ${DEVICE_FULL} mklabel gpt mkpart primary 0% 100%
sync
mkfs.ext4 -m 0 -O casefold -E nodiscard -F $PART_FULL
sync
udevadm settle
rm "$MOUNT_LOCK"

# Initialize a steam library.
/usr/lib/media-support/init-media.sh ${PART}
echo "Format complete"
exit 0
