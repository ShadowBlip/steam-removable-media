#!/bin/bash

# Originally from https://serverfault.com/a/767079
# Modified from SteamOS 3 sdcard-mount.sh
# This script is called from our systemd unit file to mount or unmount
# a system drive.

urlencode()
{
  [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

PART=$1
PART_PATH="/dev/${PART}"
PART_UUID=$(blkid -o value -s UUID ${PART_PATH})

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

url=$(urlencode ${MOUNT_POINT})

# If Steam is running, attempt to add it as a library.
if pgrep -x "steam" > /dev/null; then
  systemd-run -M 1000@ --user --collect --wait sh -c "./.steam/root/ubuntu12_32/steam steam://addlibraryfolder/${url@Q}"
fi

# Build the file structure manually, if necessary, to support desktop mode.
LIBRARY_FILE="${MOUNT_POINT}/libraryfolder.vdf"
STEAMAPPS="${MOUNT_POINT}/steamapps"
DESKTOP_LIBRARY="${MOUNT_POINT}/SteamLibrary"

if [ ! -f ${LIBRARY_FILE} ]; then
  echo '"libraryfolder"
{
	"contentid"		""
	"label"		""
}' > ${LIBRARY_FILE}
fi

if [ ! -d ${STEAMAPPS} ]; then
  mkdir ${STEAMAPPS}
fi

if [ ! -d ${DESKTOP_LIBRARY} ]; then
 ln -s ${MOUNT_POINT} ${DESKTOP_LIBRARY}
fi

chown 1000:1000 ${LIBRARY_FILE} ${STEAMAPPS} ${DESKTOP_LIBRARY}
chmod 755 ${LIBRARY_FILE}

echo "${PART_PATH} added as a steam library at ${MOUNT_POINT}"
