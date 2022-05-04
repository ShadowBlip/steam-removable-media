#!/bin/bash
# Modified from SteamOS 3 format-sdcard.sh

set -e
MEDIA=$1

# mmc devices use p as prefix for the partition number.
if [[ $MEDIA =~ mmcblk[0-9] ]]; then
	PART=${MEDIA}p1
else
	PART=${MEDIA}1
fi

# Verify root user.
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
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

# Verify device exists and start format..
if [[ -e /dev/$MEDIA ]]; then
  # User verify erase disk.
  read -n 1 -p "This will completely erase the entire disk $MEDIA. Are you sure? [Y/n]" response
  #response=${response,,} # tolower
  case "$response" in [Nn]) 
    printf "\nNo received. Aborting..."
    exit 1
    ;;&
    *)
    printf "\n"
  esac
  # Stop the service to remove the drive from steam. 
  systemctl stop media-mount@${PART}.service
  
  # Unmount any existing partitions.
  MOUNT=$(df -h | grep $MEDIA | awk '{ print $6 }')
  echo "MOUNT: $MOUNT"
  if [ ! -z "$MOUNT" ]; then
    for MNT_PART in $MOUNT
    do
    if [[ $MNT_PART = @("/"|"/boot/efi"|"/boot"|"/boot/grub") ]]; then
        echo "$MEDIA is primary OS device. Aborting..."
	exit 1
      fi
      if ! umount  $MNT_PART > /dev/null; then
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
  systemctl start media-mount@${PART}.service
  echo "Format complete"
  exit 0
else 
  echo "$MEDIA not found. Aborting..."
  exit 1
fi

exit 1
