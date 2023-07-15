#!/bin/bash
# Modified from SteamOS 3 format-device.sh

set -e

RUN_VALIDATION=1
EXTENDED_OPTIONS="nodiscard"

OPTS=$(getopt -l force,skip-validation,full,quick,device: -n format-media.sh -- "" "$@")

eval set -- "$OPTS"

while true; do
    case "$1" in
        --force) RUN_VALIDATION=0; shift ;;
        --skip-validation) RUN_VALIDATION=0; shift ;;
        --full) EXTENDED_OPTIONS="discard"; shift ;;
        --quick) EXTENDED_OPTIONS="nodiscard"; shift ;;
        --device) STORAGE_DEVICE="$2"; shift 2 ;;
        --) shift; break ;;
    esac
done

if [[ "$#" -gt 0 ]]; then
    echo "Unknown option $1"; exit 22
fi

# NVME and MMCBLK devices use a p1 prefix
case "$STORAGE_DEVICE" in
    "")
        echo "Usage: $(basename $0) [--force] [--skip-validation] [--full] [--quick] --device <device>"
        exit 19 #ENODEV
        ;;
    /dev/mmcblk?)
        STORAGE_PARTITION="${STORAGE_DEVICE}p1"
        ;;
    /dev/nvme?)
        STORAGE_PARTITION="${STORAGE_DEVICE}p1"
        ;;
    /dev/sd?)
        STORAGE_PARTITION="${STORAGE_DEVICE}1"
        ;;
    *)
        echo "Unknown or unsupported device: $STORAGE_DEVICE"
        exit 19 #ENODEV
esac

if [[ ! -e "$STORAGE_DEVICE" ]]; then
    exit 19 #ENODEV
fi

# Prompt user is device is internal
if [[ $(lsblk -d -n -r -o hotplug "$STORAGE_DEVICE") != "1" ]]; then
    echo "WARNING! $STORAGE_DEVICE is not a hotplug device and may be a system drive."
fi

STORAGE_PARTBASE="${STORAGE_PARTITION#/dev/}"

systemctl stop media-mount@"$STORAGE_PARTBASE".service

# lock file prevents the mount service from re-mounting as it gets triggered by udev rules.
#
# NOTE: Uses a shared lock filename between this and the auto-mount script to ensure we're not double-triggering nor
# automounting while formatting or vice-versa.
MOUNT_LOCK="/var/run/media-automount-${STORAGE_PARTBASE//\/_}.lock"
MOUNT_LOCK_FD=9
exec 9<>"$MOUNT_LOCK"

if ! flock -n "$MOUNT_LOCK_FD"; then
    echo "Failed to obtain lock $MOUNT_LOCK, failing"
    exit 5
fi

# Unmount any existing partitions.
MOUNTS=$(df -h | grep $STORAGE_DEVICE | awk '{print $6}')
if [ ! -z "$MOUNTS" ]; then
    for mounted_partition in $MOUNTS
    do
        for fstab_mount in $(cat /etc/fstab | awk '{ print $2 }')
        do
            if [ "$mounted_partition" = "$fstab_mount" ]; then
                echo "$STORAGE_DEVICE is mounted on $mounted_partition as part of /etc/fstab. Aborting..."
                exit 5
            fi
        done
        if ! umount $mounted_partition > /dev/null; then
            echo "Failed to unmount $mounted_partition."
            exit 5
        fi
    done
fi

# Test the sdcard
# Some fake cards advertise a larger size than their actual capacity,
# which can result in data loss or other unexpected behaviour. It is
# best to try to detect these issues as early as possible.
if [[ "$RUN_VALIDATION" != "0" ]]; then
    echo "stage=testing"
    if ! f3probe --destructive "$STORAGE_DEVICE"; then
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
            dd if=/dev/zero of="$STORAGE_DEVICE" bs=512 count=1024 # see comment in similar statement below
            if ! parted --script "$STORAGE_DEVICE" mklabel msdos mkpart primary 0% 100% ; then
                echo "Failed to create partition table: $i"
                continue # try again
            fi

            echo "Create exfat filesystem: $i"
            sync
            if ! mkfs.exfat "$STORAGE_PARTITION"; then
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

# Clear out the garbage bits generated by f3probe from the partition table sectors
# Otherwise parted may think we have existing partitions in a bogus state
dd if=/dev/zero of="$STORAGE_DEVICE" bs=512 count=1024

# Format as EXT4 with casefolding for proton compatibility
echo "stage=formatting"
sync
parted --script "$STORAGE_DEVICE" mklabel gpt mkpart primary 0% 100%
sync
mkfs.ext4 -m 0 -O casefold -E "$EXTENDED_OPTIONS" -F "$STORAGE_PARTITION"
sync
udevadm settle
echo "Format complete. Initializing steam library"

# trigger init-media
/usr/lib/media-support/init-media.sh $STORAGE_PARTITION
echo "Steam library initialized. Mounting device."

# trigger the mount service
flock -u "$MOUNT_LOCK_FD"
if ! systemctl start media-mount@"$STORAGE_PARTBASE".service; then
    echo "Failed to start mount service"
    journalctl --no-pager --boot=0 -u media-mount@"$STORAGE_PARTBASE".service
    exit 5
fi

echo "All tasks done."
exit 0
