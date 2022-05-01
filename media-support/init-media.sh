#!/bin/bash

usage()
{
  echo "Usage: $0 partition_name (e.g. sdb1)"
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

FILE="/etc/removable-libraries"
PART=$1
DEVICE="/dev/$PART"

if [[ ! -e $DEVICE ]]; then
  echo "$DEVICE not found. Aborting..."
  exit 1
fi
# Get info for this drive: $ID_FS_TYPE
eval $(/sbin/blkid -o udev ${DEVICE})

# Steam only supports ext4 right now.
if [[ ${ID_FS_TYPE} != "ext4" ]]; then
  echo "$DEVICE does not have an ext4 filesystem. Aborting..."
  exit 1
fi

# Intantiate file for tracking, if needed.
if [[ ! -f "${FILE}" ]]; then
  echo "Creating $FILE"
  touch ${FILE}
fi

# Mount service checks for UUID before adding the drive to steam.
echo "Initializing steam library."
PART_UUID=$(blkid -o value -s UUID /dev/${PART})
grep -qxF ${PART_UUID} ${FILE} || echo ${PART_UUID} >> ${FILE}
