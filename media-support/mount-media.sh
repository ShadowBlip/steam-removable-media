#!/bin/bash

# Originally from https://serverfault.com/a/767079
# Modified from SteamOS 3 sdcard-mount.sh
# This script is called from our systemd unit file to mount or unmount
# a system drive.

ACTION=$1
PART=$2
PART_PATH="/dev/${PART}"

# Identify any current mounts and known drives.
MOUNT_POINT=$(/bin/mount | /bin/grep ${PART_PATH} | /usr/bin/awk '{ print $3 }')
PART_UUID=$(blkid -o value -s UUID ${PART_PATH})

usage()
{
  echo "Usage: $0 {add|remove} partition_name (e.g. sdb1)"
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
fi


# From https://gist.github.com/HazCod/da9ec610c3d50ebff7dd5e7cac76de05
urlencode()
{
  [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

do_mount()
{
  # Verify this is an actual device because humans are flawed.
  if [[ ! -e $PART_PATH ]]; then
    echo "${PART_PATH} does not exist. Aborting..."
    exit 1
  fi

  # Avoid attempt if already mounted.
  if [[ -n ${MOUNT_POINT} ]]; then
      echo "${PART} is mounted at ${MOUNT_POINT}. Nothing to do."
      exit 0
  fi

  # Avoid mount if part of fstab but not yet mounted.
  for FSTAB_UUID in $(cat /etc/fstab | awk '{ print $1 }' | cut -d "=" -f 2)
  do
    if [ "$PART_UUID" = "$FSTAB_UUID" ]; then
      echo "$MEDIA is mounted as part of /etc/fstab. Aborting..."
      exit 0
    fi
  done

  # Get info for this drive: $ID_FS_LABEL, $ID_FS_UUID, and $ID_FS_TYPE
  eval $(/sbin/blkid -o udev ${PART_PATH})

  # Figure out a mount point to use
  LABEL=${ID_FS_LABEL}
  if [[ -z "${LABEL}" ]]; then
      LABEL=${PART}
  elif /bin/grep -q " /run/media/${LABEL} " /etc/mtab; then
      # Already in use, make a unique one
      LABEL+="-${PART}"
  fi
  MOUNT_POINT="/run/media/${LABEL}"

  /bin/mkdir -p ${MOUNT_POINT}

  # Global mount options
  OPTS="rw,noatime"

  # We need symlinks for Steam for now, so only automount ext4 as that's all
  # Steam will format right now
  if [[ ${ID_FS_TYPE} != "ext4" ]]; then
    echo "$PART_PATH does not have an ext4 filesystem. Aborting..."
    exit 0
  fi

  # Abort and throw failure if any issue with mounting occurs
  if ! /bin/mount -o ${OPTS} ${PART_PATH} ${MOUNT_POINT}; then
      echo "Error mounting ${PART} (status = $?)"
      /bin/rmdir ${MOUNT_POINT}
      exit 1
  fi

  # chown to primary system user/group
  chown 1000:1000 ${MOUNT_POINT}

  echo "** Mounted ${PART} at ${MOUNT_POINT} **"

  if [[ ! -f "${MOUNT_POINT}/SteamLibrary/libraryfolder.vdf" ]] && [[ ! -f "${MOUNT_POINT}/libraryfolder.vdf" ]]; then
      echo "Device $PART is not a steam library. Exiting..."
      exit 0
  fi

  url=$(urlencode ${MOUNT_POINT})

  # If Steam is running, attempt to add it as a library.
  if pgrep -x "steam" > /dev/null; then
      systemd-run -M 1000@ --user --collect --wait sh -c "./.steam/root/ubuntu12_32/steam steam://addlibraryfolder/${url@Q}"
  fi
  echo "${PART_PATH} added as a steam library at ${MOUNT_POINT}"
}

do_unmount()
{
  url=$(urlencode ${MOUNT_POINT})

  # If Steam is running, notify it that a library is gone.
  if pgrep -x "steam" > /dev/null; then
      systemd-run -M 1000@ --user --collect --wait sh -c "./.steam/root/ubuntu12_32/steam steam://removelibraryfolder/${url@Q}"
  fi

  # Another process may have removed it, warn user.
  if [[ -z ${MOUNT_POINT} ]]; then
      echo "Warning: ${PART} is not mounted"
  else
      /bin/umount -l ${PART_PATH}
      echo "** Unmounted ${PART} **"
  fi

  # Delete all empty dirs in /media that aren't being used as mount
  # points. This is kind of overkill, but if the drive was unmounted
  # prior to removal we no longer know its mount point, and we don't
  # want to leave it orphaned...
  for f in /run/media/* ; do
      if [[ -n $(/usr/bin/find "$f" -maxdepth 0 -type d -empty) ]]; then
          if ! /bin/grep -q " $f " /etc/mtab; then
              echo "** Removing mount point $f **"
              /bin/rmdir "$f"
          fi
      fi
  done
}

case "${ACTION}" in
  add)
      do_mount
      ;;
  remove)
      do_unmount
      ;;
  *)
      usage
      ;;
esac

