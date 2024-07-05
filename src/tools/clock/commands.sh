#!/bin/bash

source /opt/stack/commons/process.sh
source /opt/stack/commons/auth.sh
source /opt/stack/commons/error.sh
source /opt/stack/commons/logger.sh
source /opt/stack/commons/validators.sh
source /opt/stack/tools/clock/helpers.sh

# Shows the current status of system clock.
# Outputs:
#  A verbose list of text data.
show_status () {
  local query=''
  query+='Local:   \(.local_time)\n'
  query+='UTC:     \(.universal_time)\n'
  query+='RTC:     \(.rtc_time)\n'
  query+='Epoch:   \(.epoch_utc)\n'
  query+='Zone:    \(.time_zone)\n'
  query+='Clock:   \(if .rtc_in_local_tz then "Local" else "UTC" end)\n'
  query+='Synced:  \(.system_clock_synchronized)\n'
  query+='NTP:     \(.ntp_service)'

  timedatectl | jc --timedatectl | jq -cer "\"${query}\"" || return 1

  local ntp_status=''
  ntp_status="$(timedatectl timesync-status 2> /dev/null)"

  if has_not_failed; then
    local query=''
    query+='Server:  \(.server)\n'
    query+='Poll:    \(.poll_interval)\n'
    query+='Leap:    \(.leap)'

    echo ''
    echo "${ntp_status}" | jc --timedatectl | jq -cer "\"${query}\""
  fi
}

# Activates or deactivates the NTP service.
# Arguments:
#  status: on or off
set_ntp () {
  authenticate_user || return $?

  local status="${1}"

  if is_not_given "${status}"; then
    log 'Missing the status mode.'
    return 2
  elif is_not_toggle "${status}"; then
    log 'Invalid or unknown status mode.'
    return 2
  fi

  sudo timedatectl set-ntp "${status}"

  if has_failed; then
    log "Failed to set NTP to ${status}."
    return 2
  fi

  log "NTP has been set to ${status}."
}

# Sets the timezone to the given region.
# Arguments:
#  name: the name of a timezone in region/city form
set_timezone () {
  authenticate_user || return $?

  local name="${1}"

  if is_not_given "${name}"; then
    on_script_mode &&
      log 'Missing the timezone.' && return 2

    pick_timezone 'Select timezone:' || return $?
    is_empty "${REPLY}" && log 'Timezone is required.' && return 2
    name="${REPLY}"
  fi

  if is_not_timezone "${name}"; then
    log 'Invalid or unknown timezone value.'
    return 2
  fi

  sudo timedatectl set-timezone "${name}"

  if has_failed; then
    log 'Failed to set the timezone.'
    return 2
  fi
  
  log "Timezone set to ${name}."
}

# Sets the system time to the given hours and minutes.
# Arguments:
#  time: a time in hh:mm:ss form
set_time () {
  authenticate_user || return $?
  
  local time="${1}"

  if is_not_given "${time}"; then
    log 'Missing the time.'
    return 2
  elif is_not_time "${time}"; then
    log 'Invalid or malformed time.'
    return 2
  fi

  sudo timedatectl set-time "${time}"

  if has_failed; then
    log 'Failed to set the time.'
    return 2
  fi

  log "Time set to ${time}."
}

# Sets the system date to the given day, month and year.
# Arguments:
#  date: the date in yyyy-mm-dd form
set_date () {
  authenticate_user || return $?
  
  local date_value="${1}"

  if is_not_given "${date_value}"; then
    log 'Missing the date.'
    return 2
  elif is_not_date "${date_value}"; then
    log 'Invalid or malformed date.'
    return 2
  fi

  local time_value=''
  time_value=$(date +"%H:%M:%S")

  sudo timedatectl set-time "${date_value} ${time_value}"

  if has_failed; then
    log 'Failed to set the date.'
    return 2
  fi

  log "Date set to ${date_value}."
}

# Sets the hardware clock to local or UTC time.
# Arguments:
#  mode: local or utc
set_rtc () {
  authenticate_user || return $?
  
  local mode="${1}"

  if is_not_given "${mode}"; then
    log 'Missing the rtc mode.'
    return 2
  elif is_not_rtc_mode "${mode}"; then
    log 'Invalid or unknwon rtc mode.'
    return 2
  fi

  if equals "${mode}" 'local'; then
    sudo timedatectl --adjust-system-clock set-local-rtc on
  else
    sudo timedatectl --adjust-system-clock set-local-rtc off
  fi

  if has_failed; then
    log 'Failed to set hardware clock.'
    return 2
  fi

  log "Hardware clock set to ${mode} time."
}

# Synchronizes the hardware clock from the system clock.
sync_rtc () {
  authenticate_user || return $?

  sudo hwclock --systohc --utc

  if has_failed; then
    log 'Failed to sync hardware clock.'
    return 2
  fi

  log 'Hardware clock synced to system clock.'
}

# Sets the time format of the clock that is displayed
# on the user desktop status bars.
# Arguments:
#  mode:      12h or 24h
#  precision: mins, secs or nanos
format_time () {
  local mode="${1}"
  local precision="${2}"
  
  if is_not_given "${mode}"; then
    log 'Time mode is required.'
    return 2
  elif is_not_time_mode "${mode}"; then
    log 'Invalid or unknown time mode.'
    return 2
  fi

  if is_not_given "${precision}"; then
    log 'Time precision is required.'
    return 2
  elif is_not_time_precision "${precision}"; then
    log 'Invalid or unknown time precision.'
    return 2
  fi

  # Save time format and restart status bars
  save_time_format_to_settings "${mode}" "${precision}" &&
   desktop -qs init bars &> /dev/null

  if has_failed; then
    log 'Failed to set time format.'
    return 2
  fi

  log "Time format set to ${mode} mode and ${precision} precision."
}

# Sets the format of the date that is displayed
# on the user desktop status bars.
# Arguments:
#  pattern: a valid date format
format_date () {
  local pattern="${1}"
  
  if is_not_given "${pattern}"; then
    log 'Date pattern is required.'
    return 2
  fi

  # Save date format and restart status bars
  save_date_format_to_settings "${pattern}" &&
   desktop -qs init bars &> /dev/null

  if has_failed; then
    log 'Failed to set date format.'
    return 2
  fi

  log "Date format set to $(date "+${pattern}")."
}

