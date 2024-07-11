#!/bin/bash

source /opt/stack/commons/error.sh
source /opt/stack/commons/math.sh
source /opt/stack/commons/validators.sh

# Find all the packages installed to the system
# via the package managers pacman and yay (aur).
# Returns:
#  A JSON object with the pacman and aur list packages.
find_installed_packages () {
  local query='[inputs|split(" ")|{name: .[0], version: .[1]}]'
  
  local pacman_pkgs=''
  pacman_pkgs="$(pacman -Qn | jq -Rn "${query}")" || return 1
  
  local aur_pkgs=''
  aur_pkgs="$(pacman -Qm | jq -Rn "${query}")" || return 1

  echo "{\"pacman\": ${pacman_pkgs}, \"aur\": ${aur_pkgs}}"
}

# Find the list of packages need to be updated.
# Returns:
#  A JSON object with pacman and aur list of outdated packages.
find_outdated_packages () {
  local query=''
  query+='name: .[0]|split(" ")|.[0],'
  query+='current: .[0]|split(" ")|.[1],'
  query+='latest: .[1]'
  query="[inputs|split(\" -> \")|{${query}}]"
  
  # List all outdated packages installed via pacman
  local pacman_pkgs=''
  pacman_pkgs="$(checkupdates 2> /dev/null | jq -Rn "${query}")"

  if is_true "$? = 1"; then
    return 1
  elif is_true "$? = 2"; then
    pacman_pkgs='[]'
  fi

  # List all outdated packages installed via the aur repos
  local aur_pkgs=''
  aur_pkgs="$(yay -Qum 2> /dev/null | jq -Rn "${query}")"

  if has_failed; then
    aur_pkgs='[]'
  fi

  echo "{\"pacman\": ${pacman_pkgs}, \"aur\": ${aur_pkgs}}"
}

# Checks if the given value is a valid package repository.
# Arguments:
#  value: pacman or aur
is_package_repository () {
  local value="${1}"

  if not_match "${value}" '^(pacman|aur)$'; then
    return 1
  fi

  return 0
}

# An inverese alias of the is_package_repository.
is_not_package_repository () {
  is_package_repository "${1}" && return 1 || return 0
}

