#!/bin/bash

usage()
{
  echo "Usage: $0 partition_name (e.g. sdb1)"
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

LIBRARY="/etc/removable-libraries"
PART=$1
PART_PATH="/dev/$PART"

# Check if device exists.
if [[ ! -e $PART_PATH ]]; then
  echo "$PART not found. Aborting..."
  exit 1
fi

# Get info for this drive: $ID_FS_TYPE
eval $(/sbin/blkid -o udev ${PART_PATH})

# Steam only supports ext4 right now.
if [[ ${ID_FS_TYPE} != "ext4" ]]; then
  echo "$PART does not have an ext4 filesystem. It uses ${ID_FS_TYPE} and is
not supported. Aborting..."
  exit 1
fi

# Intantiate file for tracking, if needed.
if [[ ! -f "${LIBRARY}" ]]; then
  echo "Creating $LIBRARY"
  touch ${LIBRARY}
fi

# Mount service checks for UUID before adding the drive to steam.
echo "Initializing steam library."
DEV_UUID=$(blkid -o value -s UUID $PART_PATH)
grep -qxF ${DEV_UUID} ${LIBRARY} || echo ${DEV_UUID} >> ${LIBRARY}

systemctl start media-mount@${PART}.service
exit 0
