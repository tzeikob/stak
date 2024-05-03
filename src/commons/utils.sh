#!/bin/bash

set -Eeo pipefail

source /opt/stack/commons/logger.sh
source /opt/stack/commons/validators.sh

SETTINGS_FILE='/opt/stack/.settings'

# Aborts the current process logging the given error message.
# Arguments:
#  level:   optionally one of INFO, WARN, ERROR
#  message: an error message to print
# Outputs:
#  An error messsage.
abort () {
  local level message

  if [[ $# -ge 2 ]]; then
    level="${1}"
    message="${2}"
  elif [[ $# -eq 1 ]]; then
    message="${1}"
  fi

  # If level is given script is logging, otherwise screen is logging
  if is_given "${message}"; then
    if is_given "${level}"; then
      log "${level}" "${message}"
      log "${level}" 'Process has been exited.'
    else
      log "\n${message}"
      log 'Process has been exited.'
    fi
  else
    if is_given "${level}"; then
      log "${level}" 'Process has been exited.'
    else
      log '\nProcess has been exited.'
    fi
  fi

  exit 1
}

# Checks if the given exit status code is non-zero
# which indicates the last command has failed. If no
# code is given the function will consider as exit
# code the current value of $?.
# Arguments:
#  code: an exit status code
# Returns:
#  0 if exit code is non-zero otherwise 1.
has_failed () {
  # Save exit code set by the previous command
  local code=$?

  if is_given "${1}"; then
    code="${1}"
  fi

  if [[ ${code} -ne 0 ]]; then
    return 0
  fi

  return 1
}

# An inverse version of has_failed.
has_not_failed () {
  has_failed "${1}" && return 1 || return 0
}

# Resets the installation settings.
init_settings () {
  echo '{}' > "${SETTINGS_FILE}"
}

# Saves the installation setting with the given key
# to the given value.
# Arguments:
#  key:   the key name of a setting
#  value: any value
save_setting () {
  local key="${1}"
  local value="${2}"

  if is_empty "${value}" || match "${value}" '^ *$'; then
    value='""'
  fi

  local settings=''
  settings="$(jq -cr ".${key} = ${value}" "${SETTINGS_FILE}")"

  echo "${settings}" > "${SETTINGS_FILE}"
}

# Returns the content of the installation settings file.
# Outputs:
#  The installation settings as a JSON object.
get_settings () {
  jq '.' "${SETTINGS_FILE}"
}

# Gets the value of the installation setting with the given key.
# Arguments:
#  key: the key name of a setting
# Outputs:
#  The value of the given setting otherwise none.
get_setting () {
  local key="${1}"

  jq -cer ".${key}" "${SETTINGS_FILE}"
}

# Checks if the setting with the given key is equal
# to the given value.
# Arguments:
#  key:   the key of a setting
#  value: any value
# Returns:
#  0 if the setting is equal to the value otherwise 1.
is_setting () {
  local key="${1}"
  local value="${2}"

  # Check if the given value is of invalid type
  echo "${value}" | jq -cer 'type' &> /dev/null

  # Consider any value of invalid type as string
  if has_failed; then
    value="\"${value}\""
  fi

  local query="select(.${key} == ${value})"

  jq -cer "${query}" "${SETTINGS_FILE}" &> /dev/null
}

# Removes leading and trailing white spaces
# from the given string or input.
# Arguments:
#  input: a string or input of a pipeline
# Outputs:
#  The given input trimmed of trailing spaces.
trim () {
  local input=''

  if [[ -p /dev/stdin ]]; then
    input="$(cat -)"
  else
    input="$@"
  fi

  echo "${input}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Checks if the dep with the given name is installed or not.
# Arguments:
#  name: the name of a dependency
# Returns:
#  0 if dep is installed otherwise 1.
dep_exists () {
  local name="${1}"

  if pacman -Qi "${name}" > /dev/null 2>&1; then
    return 0
  fi

  return 1
}

# An inversed alias of dep_exists.
dep_not_exists () {
  dep_exists "${1}" && return 1 || return 0
}
