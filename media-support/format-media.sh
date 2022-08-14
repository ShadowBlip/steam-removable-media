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

MEDIA=$1

# mmc and nvme devices use p as prefix for the partition number.
if [[ $MEDIA =~ mmcblk[0-9] || $MEDIA =~ nvme[0-9]n[0-9] ]]; then
	PART=${MEDIA}p1
else
	PART=${MEDIA}1
fi

# Verify device exists and start format..
if [[ -e /dev/$MEDIA ]]; then

  # User verify erase disk.
  read -n 1 -p "This will completely erase the entire disk $MEDIA. Are you sure? [Y/n]" response
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
  MOUNT=$(df -h | grep $MEDIA | awk '{print $6}')
  if [ ! -z "$MOUNT" ]; then
    for MNT_PART in $MOUNT
    do
      for FSTAB_MNT in $(cat /etc/fstab | awk '{ print $2 }')
      do
        if [ "$MNT_PART" = "$FSTAB_MNT" ]; then
          echo "$MEDIA is mounted on $MNT_PART and is part of /etc/fstab. Aborting..."
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
  parted --script /dev/${MEDIA} mklabel gpt mkpart primary 0% 100%
  sync
  mkfs.ext4 -m 0 -O casefold -F /dev/${PART}
  sync

  # Initialize a steam library.
  /usr/lib/media-support/init-media.sh ${PART}
  echo "Format complete"
  exit 0
else 
  echo "$MEDIA not found. Aborting..."
  exit 1
fi

exit 0
