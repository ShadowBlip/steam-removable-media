#!/bin/bash

# Originally from https://serverfault.com/a/767079
# Modified from SteamOS 3 steamos-automount.sh
# This script is called from our systemd unit file to mount or unmount
# a system drive.

set -euo pipefail

usage()
{
  echo "Usage: $0 {add|remove|retrigger} device_name (e.g. sdb1)"
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
fi

ACTION=$1
DEVBASE=$2
DEVICE="/dev/${DEVBASE}"

# Shared between this and the auto-mount script to ensure we're not double-triggering nor automounting while formatting
# or vice-versa.
MOUNT_LOCK="/var/run/media-automount-${DEVBASE//\/_}.lock"

# Identify any current mounts and known drives.
DEVICE_UUID=$(blkid -o value -s UUID ${DEVICE})

# Obtain lock
exec 9<>"$MOUNT_LOCK"
if ! flock -n 9; then
  echo "$MOUNT_LOCK is active: ignoring action $ACTION"
  # Do not return a success exit code: it could end up putting the service in 'started' state without doing the mount
  # work (further start commands will be ignored after that)
  exit 1
fi

# Wait N seconds for steam
wait_steam()
{
  local i=0
  local wait=$1
  echo "Waiting up to $wait seconds for steam to load"
  while ! pgrep -x steamwebhelper &>/dev/null && (( i++ < wait )); do
    sleep 1
  done
}

send_steam_url()
{
  local command="$1"
  if pgrep -x "steam" > /dev/null; then
    local mount_point=$2
    url=$(urlencode "${mount_point}")
    echo "Sending URL to steam: steam://${command}/${url}"
    systemd-run -M 1000@ --user --collect --wait sh -c "./.steam/root/ubuntu12_32/steam steam://${command}/${url@Q}"
  fi
}

# From https://gist.github.com/HazCod/da9ec610c3d50ebff7dd5e7cac76de05
urlencode()
{
  [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

do_mount()
{
  # Avoid mount if part of fstab but not yet mounted.
  for FSTAB_UUID in $(cat /etc/fstab | awk '{ print $1 }' | cut -d "=" -f 2)
  do
   if [ "$DEVICE_UUID" = "$FSTAB_UUID" ]; then
     echo "$MEDIA is mounted as part of /etc/fstab. Aborting..."
     exit 0
   fi
  done

  # Get info for this drive: $ID_FS_LABEL, and $ID_FS_TYPE
  dev_json=$(lsblk -o PATH,LABEL,FSTYPE --json -- "$DEVICE" | jq '.blockdevices[0]')
  ID_FS_LABEL=$(jq -r '.label | select(type == "string")' <<< "$dev_json")
  ID_FS_TYPE=$(jq -r '.fstype | select(type == "string")' <<< "$dev_json")

  # Global mount options
  OPTS="rw,noatime"

  # Prior to talking to udisks, we need all udev hooks (we were started by one) to finish, so we know it has knowledge
  # of the drive.  Our own rule starts us as a service with --no-block, so we can wait for rules to settle here
  # safely.
  if ! udevadm settle; then
    echo "Failed to wait for \`udevadm settle\`"
    exit 1
  fi

  # Ask udisks to auto-mount.  Since this API doesn't let us pass a username to automount as, we need to drop to the
  # user.  Don't do this as a `--user` unit though as their session may not be running.
  # This requires the paired polkit file to allow the user the filesystem-mount-other-seat permission.
  ret=0
  reply=$(systemd-run --uid=1000 --pipe \
    busctl call --allow-interactive-authorization=false --expect-reply=true --json=short \
    org.freedesktop.UDisks2 \
    /org/freedesktop/UDisks2/block_devices/"${DEVBASE}" \
    org.freedesktop.UDisks2.Filesystem Mount 'a{sv}' 2 \
    auth.no_user_interaction b true \
    options s "$OPTS") || ret=$?

  if [[ $ret -ne 0 ]]; then
    echo "Error mounting ${DEVICE} -- (status = $ret)"
    echo "--- $[reply] ---"
    exit 1
  fi

  # Expected reply is of the format
  #  {"type":"s","data":["/run/media/$USER/$DEVICE_UUID"]}
  mount_point=$(jq -r '.data[0] | select(type == "string")' <<< "$reply" || true)
  if [[ -z $mount_point ]]; then
    echo "Error when mounting ${DEVICE}: udisks returned success but could not parse reply:"
    echo "--- $[reply] ---"
    exit 2
  fi

  echo "Mounted ${DEVICE} at ${mount_point}"

  if [ -d "${mount_point}/lost+found" ]; then
    rm -rf "${mount_point}/lost+found"
  fi

  # Check if this is a steam library.
  steamapps_dir="${mount_point}/steamapps"
  if [ ! -d ${steamapps_dir} ]; then
    echo "Unable to find a steamapps dir. Device is not a library. Run init-media to build steam library. Nothing else to do."
    return
  # If Steam is running, notify it.
  else
    send_steam_url "addlibraryfolder" $mount_point
    echo "${DEVICE} added as a steam library at ${mount_point}"
  fi
}

do_unmount()
{
  # If Steam is running, notify it
  local mount_point=$(findmnt -fno TARGET "${DEVICE}" || true)
  [[ -n $mount_point ]] || return 0
  send_steam_url "removelibraryfolder" $mount_point
}

do_retrigger()
{
  local mount_point=$(findmnt -fno TARGET "${DEVICE}" || true)
  [[ -n $mount_point ]] || return 0

  # In retrigger mode, we want to wait a bit for steam as the common pattern is starting in parallel with a retrigger
  wait_steam 10
  # This is a truly gnarly way to ensure steam is ready for commands.
  # TODO literally anything else
  sleep 6
  send_steam_url "addlibraryfolder" $mount_point
}

case "${ACTION}" in
  add)
    do_mount
    ;;
  remove)
    do_unmount
    ;;
  retrigger)
    do_retrigger
    ;;
  *)
    usage
    ;;
esac
