#!/bin/bash

# Originally from https://serverfault.com/a/767079
# Modified from SteamOS 3 steamos-automount.sh
# This script is called from our systemd unit file to set up
# the device as a steam library.

set -euo pipefail

# Identify drive, any current mounts, and if it is aknown drive.
DEVBASE=$1
DEVICE="/dev/${DEVBASE}"
DEVICE_UUID=$(blkid -o value -s UUID ${DEVICE})
mount_point=$(/bin/mount | /bin/grep ${DEVICE} | /usr/bin/awk '{ print $3 }')

usage()
{
  echo "Usage: $0 partition_name (e.g. sdb1)"
  exit 1
}

do_init()
{
  # Avoid mount if part of fstab but not yet mounted.
  for FSTAB_UUID in $(cat /etc/fstab | awk '{ print $1 }' | cut -d "=" -f 2)
  do
   if [ "$DEVICE_UUID" = "$FSTAB_UUID" ]; then
     echo "$MEDIA is mounted as part of /etc/fstab. Aborting..."
     exit 1
   fi
  done

  # check if already mounted
  SKIP_MOUNT=0
  if [[ -n ${mount_point} ]]; then
      echo "${DEVICE} is mounted at ${mount_point}"
      SKIP_MOUNT=1
  fi

  # We need symlinks for Steam for now, so only automount ext4 as that's all
  # Steam will format right now
  #if [[ ${ID_FS_TYPE} != "ext4" ]]; then
  #  echo "Error mounting ${DEVICE}: wrong fstype: ${ID_FS_TYPE} - ${dev_json}"
  #  exit 0
  #fi

  # Prior to talking to mounting, we need all udev hooks to finish, so we know the system has
  # knowledge of the drive. Our rule starts us as a service with --no-block, so we can wait
  # for rules to settle here safely.
  if ! udevadm settle; then
    echo "Failed to wait for \`udevadm settle\`"
    exit 1
  fi

  # Get info for this drive: $ID_FS_LABEL, $ID_FS_UUID, and $ID_FS_TYPE
  if [ $SKIP_MOUNT == 0 ]; then
    # Figure out a mount point to use
    eval $(/sbin/blkid -o udev ${DEVICE})
    LABEL=${ID_FS_LABEL}
    if [[ -z "${LABEL}" ]]; then
        LABEL=${DEVBASE}
    elif /bin/grep -q " /run/media/${LABEL} " /etc/mtab; then
        # Already in use, make a unique one
        LABEL+="-${DEVBASE}"
    fi
    mount_point="/run/media/${LABEL}"

    /bin/mkdir -p ${mount_point}

    ## Mount the device, throw an error if any issue with mounting occurs.
    if [ ! /bin/mount -o ${OPTS} ${DEVICE} ${mount_point} ]; then
        echo "Error mounting ${DEVICE} (status = $?)"
        /bin/rmdir ${mount_point}
        exit 1
    fi

    echo "Mounted ${DEVICE} at ${mount_point}"
  fi

  if [ -d "${mount_point}/lost+found" ]; then
    rm -rf "${mount_point}/lost+found"
  fi

  # Build the file structure manually, if necessary.
  steamapps_dir="${mount_point}/steamapps"
  if [ ! -d ${steamapps_dir} ]; then
    echo "steamapps dir not found. Creating..."
    mkdir ${steamapps_dir}
    chmod 755 ${steamapps_dir}
  fi

  library_file="${mount_point}/libraryfolder.vdf"
  if [ ! -f ${library_file} ]; then
    echo "libraryfolder.vdf not found. Creating..."
    echo '"libraryfolder"
  {
  	"contentid"		""
  	"label"		""
  }' > ${library_file}
    chown 1000:1000 ${library_file}
  fi

  desktop_dir="${mount_point}/SteamLibrary"
  if [ -L ${desktop_dir} ]; then
    echo "Removing old symlink to ${desktop_dir}"
    rm ${desktop_dir}
  fi

  if [ ! -d ${desktop_dir} ]; then
    echo "Desktop Libray not found. Creating..."
    mkdir ${desktop_dir}
  fi

  if [ ! -L "${desktop_dir}/steamapps" ]; then
    echo "Adding symlink to steamapps dir"
    ln -s ${steamapps_dir} "${desktop_dir}/steamapps"
  fi

  if [ ! -L "${desktop_dir}/libraryfolder.vdf" ]; then
    echo "Adding symlink to libraryfolder.vdf"
    ln -s ${library_file} "${desktop_dir}/libraryfolder.vdf"
  fi

  chown -R 1000:1000 ${steamapps_dir}
  chmod 755 ${library_file}
  chown -R 1000:1000 ${desktop_dir}
  chmod 755 "${desktop_dir}/libraryfolder.vdf"

  # Clean up if we mounted ourself
  if [ $SKIP_MOUNT == 0 ]; then
    /bin/umount ${mount_point}
    echo "Unmounted ${DEVICE} from ${mount_point}."
  fi
  echo "Steam Library initialized."
  exit 0
}

if [ ! -f $DEVICE ]; then {
  usage
}
do_init

