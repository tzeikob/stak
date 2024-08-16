#!/bin/bash

set -Eeo pipefail

source src/commons/process.sh
source src/commons/error.sh
source src/commons/logger.sh
source src/commons/validators.sh

SETTINGS=./settings.json

# Synchronizes the system clock to the current time.
sync_clock () {
  log INFO 'Updating the system clock...'

  local timezone=''
  timezone="$(jq -cer '.timezone' "${SETTINGS}")" ||
    abort ERROR 'Unable to read timezone setting.'

  timedatectl set-timezone "${timezone}" 2>&1 ||
    abort ERROR 'Unable to set timezone.'

  log INFO "Timezone has been set to ${timezone}."

  timedatectl set-ntp true 2>&1 ||
    abort ERROR 'Failed to enable NTP mode.'

  log INFO 'NTP mode has been enabled.'

  while timedatectl status 2>&1 | grep -q 'System clock synchronized: no'; do
    sleep 1
  done

  timedatectl status 2>&1 ||
    abort ERROR 'Failed to show system time status.'

  log INFO 'System clock has been updated.'
}

# Sets the pacman mirrors list.
set_mirrors () {
  log INFO 'Setting up package databases mirrors list...'

  local mirrors=''
  mirrors="$(jq -cer '.mirrors|join(",")' "${SETTINGS}")" ||
    abort ERROR 'Unable to read mirrors setting.'

  reflector --country "${mirrors}" \
    --age 48 --sort age --latest 40 --save /etc/pacman.d/mirrorlist 2>&1 ||
    abort ERROR 'Failed to fetch package databases mirrors.'

  log INFO "Package databases mirrors set to ${mirrors}."
}

# Synchronizes package databases with the master.
sync_package_databases () {
  log INFO 'Starting to synchronize package databases...'

  local lock_file='/var/lib/pacman/db.lck'

  if file_exists "${lock_file}"; then
    log WARN 'Package databases seem to be locked.'

    rm -f "${lock_file}" ||
      abort ERROR "Unable to remove the lock file ${lock_file}."

    log INFO "Lock file ${lock_file} has been removed."
  fi

  local keyserver='hkp://keyserver.ubuntu.com'

  echo "keyserver ${keyserver}" >> /etc/pacman.d/gnupg/gpg.conf ||
    abort ERROR 'Failed to add the GPG keyserver.'

  log INFO "GPG keyserver has been set to ${keyserver}."

  sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf ||
    abort ERROR 'Failed to enable parallel downloads.'

  pacman -Syy 2>&1 ||
    abort ERROR 'Failed to synchronize package databases.'

  log INFO 'Package databases synchronized to the master.'
}

# Updates the keyring package.
update_keyring () {
  log INFO 'Updating the archlinux keyring...'

  pacman -Sy --needed --noconfirm archlinux-keyring 2>&1 ||
    abort ERROR 'Failed to update keyring.'

  log INFO 'Keyring has been updated successfully.'
}

# Installs the linux kernel.
install_kernel () {
  log INFO 'Installing the linux kernel...'

  local kernel=''
  kernel="$(jq -cer '.kernel' "${SETTINGS}")" ||
    abort ERROR 'Unable to read kernel setting.'

  local pkgs=''

  if equals "${kernel}" 'stable'; then
    pkgs='linux linux-headers'
  elif equals "${kernel}" 'lts'; then
    pkgs='linux-lts linux-lts-headers'
  fi

  if is_empty "${pkgs}"; then
    abort ERROR 'No linux kernel packages set for installation.'
  fi

  pacstrap /mnt base ${pkgs} linux-firmware archlinux-keyring reflector rsync sudo jq 2>&1 ||
    abort ERROR 'Failed to pacstrap kernel and base packages.'

  log INFO 'Linux kernel has been installed.'
}

# Copies the installation files to new system.
copy_installation_files () {
  log INFO 'Copying installation files to new system...'

  local target='/mnt/stack'

  rm -rf "${target}" && rsync -av . "${target}" ||
    abort ERROR 'Unable to copy installation files.'

  log INFO 'Installation files have been copied.'
}

# Grants the nopasswd permission to the wheel user group.
grant_permissions () {
  local rule='%wheel ALL=(ALL:ALL) NOPASSWD: ALL'

  sed -i "s/^# \(${rule}\)/\1/" /mnt/etc/sudoers ||
    abort ERROR 'Failed to grant nopasswd permission.'

  if ! grep -q "^${rule}" /mnt/etc/sudoers; then
    abort ERROR 'Failed to grant nopasswd permission.'
  fi

  log INFO 'Sudoer nopasswd permission has been granted.'
}

log INFO 'Script bootstrap.sh started.'
log INFO 'Starting the bootstrap process...'

sync_clock &&
  set_mirrors &&
  sync_package_databases &&
  update_keyring &&
  install_kernel &&
  copy_installation_files &&
  grant_permissions 

log INFO 'Script bootstrap.sh has finished.'

resolve bootstrap 660 && sleep 2