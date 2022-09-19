#!/usr/bin/env bash

set -Eeo pipefail

revoke () {
  local PERMISSION=$1

  case "$PERMISSION" in
   "nopasswd")
    sed -i 's/^\(%wheel ALL=(ALL:ALL) NOPASSWD: ALL\)/# \1/' /mnt/etc/sudoers;;
  esac

  echo "Permission $PERMISSION has been revoked"
}

clean_up () {
  echo "Cleaning up the system..."

  rm -rf /mnt/root/stack
  rm -rf "/mnt/home/$USERNAME/stack"

  echo "Installation files have been removed"
  echo "System clean up has been completed"
}

unmount () {
  umount -R /mnt &&
    echo "Partitions under /mnt have been unmounted" ||
    echo "Ignoring any busy mount points"
}

restart () {
  echo "Rebooting the system in 15 secs (ctrl-c to skip)..."
  sleep 15

  cp "$LOG" "/mnt/home/$USERNAME/stack.log"
  reboot
}

echo -e "\nBooting into the system for the first time..."

source "$OPTIONS"

revoke "nopasswd" &&
  clean_up &&
  unmount &&
  restart
