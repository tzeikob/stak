#!/bin/bash

source src/commons/process.sh
source src/commons/auth.sh
source src/commons/error.sh
source src/commons/logger.sh
source src/commons/math.sh
source src/commons/validators.sh
source src/tools/power/helpers.sh

# Shows the current status of the system's power.
# Outputs:
#  A verbose list of text data.
show_status () {
  local space=15

  local query='if ."on-line" then "on" else "off" end | lbln("Adapter")'

  find_adapter | jq -cer --arg SPC ${space} "${query}" || return 1

  local battery=''
  battery="$(find_battery)" || return 1

  if is_not_empty "${battery}"; then
    local query=''
    query+='\("yes"                              | lbln("Battery"))'
    query+='\(.state | downcase)                 | lbln("State"))'
    query+='\(.charge_percent | unit("%")        | lbln("Charge"))'
    query+="\(.design_capacity_mah | unit("mAh") | lbln("Capacity"))"

    echo "${battery}" | jq -cer --arg SPC ${space} "\"${query}\"" || return 1
  else
    echo '"no"' | jq -cer --arg SPC ${space} 'lbln("Battery")' || return 1
  fi

  if file_exists '/sys/class/power_supply/BAT0/current_now'; then
    local current_now=''
    current_now="$(< /sys/class/power_supply/BAT0/current_now)"

    echo "\"${current_now}\"" | jq -cer --arg SPC ${space} 'unit("mAh") | lbln("Current")'
  fi

  if file_exists '/sys/class/power_supply/BAT0/charge_now'; then
    local charge_now=''
    charge_now="$(< /sys/class/power_supply/BAT0/charge_now)"

    echo "\"${charge_now}\"" | jq -cer --arg SPC ${space} 'unit("mAh") | lbln("Load")'
  fi

  local query='.[] | select(.unit == "acpid.service") | .active | olbln("ACPID")'

  systemctl -a | jc --systemctl | jq -cr --arg SPC ${space} "${query}" || return 1

  local query='.[] | select(.unit == "tlp.service") | .active | olbln("TLP")'

  systemctl -a | jc --systemctl | jq -cr "${query}" || return 1

  local config_file='/etc/tlp.d/00-main.conf'

  local index=0
  for index in 0 1; do
    local start=''
    start="$(grep -E "^START_CHARGE_THRESH_BAT${index}=" "${config_file}" | cut -d '=' -f 2)"
    
    local stop=''
    stop="$(grep -E "^STOP_CHARGE_THRESH_BAT${index}=" "${config_file}" | cut -d '=' -f 2)"
    
    if is_not_empty "${start}" || is_not_empty "${stop}"; then
      echo "[${start:-0}%", "${stop:-100}%]" | jq -cer --arg SPC ${space} "lbln("Charge[${index}]")"
    fi
  done

  if file_exists "${POWER_SETTINGS}"; then
    local query='.screensaver.interval | unit("mins") | lbln("Screensaver"; "Off")'

    jq -cr --arg SPC ${space} "${query}" "${POWER_SETTINGS}" || return 1
  else
    echo '"off"' | jq -cer --arg SPC ${space} 'lbln("Screensaver")'
  fi

  loginctl show-session | awk -v SPC=${space} '{
    match($0,/(.*)=(.*)/,a)

    if (a[1] == "Docked") {
      a[1]="Docked"
    } else if (a[1] == "LidClosed") {
      a[1]="Lid Down"
    } else {
      next
    }

    if (!a[2] || a[2] ~ /^[[:blank:]]*$/) a[2] = "N/A"

    frm = "%-"SPC"s%s\n"
    printf frm, a[1]":", a[2]
  }' || return 1

  echo

  loginctl show-session | awk awk -v SPC=${space} '{
    match($0,/(.*)=(.*)/,a)

    if (a[1] == "HandlePowerKey") {
      a[1]="On Power"
    } else if (a[1] == "HandleRebootKey") {
      a[1]="On Reboot"
    } else if (a[1] == "HandleSuspendKey") {
      a[1]="On Suspend"
    } else if (a[1] == "HandleHibernateKey") {
      a[1]="On Hibernate"
    } else if (a[1] == "HandleLidSwitch") {
      a[1]="On Lid Down"
    } else if (a[1] == "HandleLidSwitchDocked") {
      a[1]="On Docked"
    } else if (a[1] == "IdleAction") {
      a[1]="On Idle"
    } else {
      next
    }

    if (!a[2] || a[2] ~ /^[[:blank:]]*$/) a[2] = "N/A"

    frm = "%-"SPC"s%s\n"
    printf frm, a[1]":", a[2]
  }' || return 1
}

# Sets the action of the handler with the given name.
# Arguments:
#  handler: power, reboot, suspend, lid or docked
#  action:  poweroff, reboot, suspend or ignore
set_action () {
  authenticate_user || return $?

  local handler="${1}"
  local action="${2}"

  if is_not_given "${handler}"; then
    on_script_mode &&
      log 'Missing the power handler.' && return 2

    pick_power_handler || return $?
    is_empty "${REPLY}" && log 'Power handler is required.' && return 2
    handler="${REPLY}"
  fi

  if is_not_power_handler "${handler}"; then
    log 'Invalid power handler.'
    return 2
  fi

  if is_not_given "${action}"; then
    on_script_mode &&
      log 'Missing power action.' && return 2

    pick_power_action || return $?
    is_empty "${REPLY}" && log 'Power action is required.' && return 2
    action="${REPLY}"
  fi

  if is_not_power_action "${action}"; then
    log 'Invalid power action.'
    return 2
  fi

  # Resolve the logind config option for the handler
  local option=''
  option="$(convert_handler_to_option "${handler}")" || return 1

  local config_file='/etc/systemd/logind.conf.d/00-main.conf'

  # Copy the default config file if not yet created
  if file_not_exists "${config_file}"; then
    sudo mkdir -p /etc/systemd/logind.conf.d
    sudo cp /etc/systemd/logind.conf "${config_file}"
  fi

  if grep -qE "^${option}=" "${config_file}"; then
    sudo sed -i "s/^\(${option}=\).*/\1${action}/" "${config_file}"
  else
    echo "${option}=${action}" | sudo tee -a "${config_file}" > /dev/null
  fi

  sudo systemctl kill -s HUP systemd-logind

  if has_failed; then
    log "Failed to set ${handler} action."
    return 2
  fi

  log "Action ${handler} set to ${action}."
}

# Resets the action of all power handlers.
reset_actions () {
  authenticate_user || return $?

  local config_file='/etc/systemd/logind.conf.d/00-main.conf'

  if file_not_exists "${config_file}"; then
    log 'Actions already set to defaults.'
    return 2
  fi

  sudo sed -i '/^HandlePowerKey=.*/d' "${config_file}"
  sudo sed -i '/^HandleRebootKey=.*/d' "${config_file}"
  sudo sed -i '/^HandleSuspendKey=.*/d' "${config_file}"
  sudo sed -i '/^HandleLidSwitch=.*/d' "${config_file}"
  sudo sed -i '/^HandleLidSwitchDocked=.*/d' "${config_file}"

  sudo systemctl kill -s HUP systemd-logind

  if has_failed; then
    log 'Failed to reset power actions.'
    return 2
  fi

  log 'Power actions have been reset.'
}

# Sets the interval time of the screen saver, where
# 0 means deactivate the screensaver.
# Arguments:
#  interval: the number of minutes or 0
set_screensaver () {
  local interval="${1}"

  if is_not_given "${interval}"; then
    log 'Missing interval time.'
    return 2
  elif is_not_integer "${interval}"; then
    log 'Invalid interval time.'
    return 2
  elif is_not_integer "${interval}" '[0,60]'; then
    log 'Interval time out of range.'
    return 2
  fi

  if is_true "${interval} > 0"; then
    local secs=0
    secs="$(calc "${interval} * 60")" || return 1

    xset s "${secs}" "${secs}" &> /dev/null
  else
    xset s off &> /dev/null
  fi
  
  if has_failed; then
    log 'Failed to set the screen saver.'
    return 2
  fi

  log "Screen saver set to ${interval} mins."
  
  save_screen_saver_to_settings "${interval}" ||
    log 'Failed to save screen saver to settings.'
}

# Initiates the screen saver to the interval saved
# in the settings file.
init_screensaver () {
  local interval=5

  if file_exists "${POWER_SETTINGS}"; then
    interval="$(jq '.screensaver.interval//5' "${POWER_SETTINGS}")"
  fi
 
  if is_true "${interval} > 0"; then
    local secs=0
    secs="$(calc "${interval} * 60")" || return 1

    xset s "${secs}" "${secs}" &> /dev/null
  else
    xset s off &> /dev/null
  fi
  
  if has_failed; then
    log 'Failed to initialize the screen saver.'
    return 2
  fi

  log "Screen saver initialized to ${interval} mins."
}

# Enables or disables power saving mode via the tlp service.
# Arguments:
#  status: on or off
set_tlp () {
  authenticate_user || return $?

  local status="${1}"

  if is_not_given "${status}"; then
    log 'Missing the power saving status.'
    return 2
  elif is_not_toggle "${status}"; then
    log 'Invalid power saving status.'
    return 2
  fi

  if is_on "${status}"; then
    log 'Enabling power saving mode...'
    sudo systemctl stop acpid.service &> /dev/null &&
    sudo systemctl disable acpid.service &> /dev/null &&
    sudo systemctl enable tlp.service &> /dev/null &&
    sudo systemctl start tlp.service &> /dev/null &&
    sudo systemctl daemon-reload
  else
    log 'Disabling power saving mode...'
    sudo systemctl stop tlp.service &> /dev/null &&
    sudo systemctl disable tlp.service &> /dev/null &&
    sudo systemctl enable acpid.service &> /dev/null &&
    sudo systemctl start acpid.service &> /dev/null &&
    sudo systemctl daemon-reload
  fi

  if has_failed; then
    log "Failed to set power saving mode to ${status}."
    return 2
  fi

  log "Power saving mode set to ${status}."
}

# Sets the battery charging start/stop thresholds to the given
# percentage limits.
# Arguments:
#  start: the percent of capacity to start charging
#  stop:  the percent of capacity to stop charging
set_charging () {
  authenticate_user || return $?

  local start="${1}"
  local stop="${2}"

  if is_not_given "${start}"; then
    log 'Missing the charging start threshold.'
    return 2
  elif is_not_integer "${start}"; then
    log 'Invalid charging start threshold.'
    return 2
  elif is_not_integer "${start}" '[0,100]'; then
    log 'Charging start threshold is out of range.'
    return 2
  fi

  if is_not_given "${stop}"; then
    log 'Missing the charging stop threshold.'
    return 2
  elif is_not_integer "${stop}"; then
    log 'Invalid charging stop threshold.'
    return 2
  elif is_not_integer "${stop}" '[0,100]'; then
    log 'Charging stop threshold is out of range.'
    return 2
  fi

  if is_true "${start} >= ${stop}"; then
    log 'Start threshold should be lower than stop.'
    return 2
  fi

  local config_file='/etc/tlp.d/00-main.conf'

  if file_not_exists "${config_file}"; then
    sudo rm -f /etc/tlp.d/00-template.conf
    sudo touch "${config_file}"
  fi

  local index=0
  for index in 0 1; do
    if grep -qE "^START_CHARGE_THRESH_BAT${index}=" "${config_file}"; then
      sudo sed -i "s/^\(START_CHARGE_THRESH_BAT${index}=\).*/\1${start}/" "${config_file}"
    else
      echo "START_CHARGE_THRESH_BAT${index}=${start}" | sudo tee -a "${config_file}" > /dev/null
    fi
    
    if grep -qE "^STOP_CHARGE_THRESH_BAT${index}=" "${config_file}"; then
      sudo sed -i "s/^\(STOP_CHARGE_THRESH_BAT${index}=\).*/\1${stop}/" "${config_file}"
    else
      echo "STOP_CHARGE_THRESH_BAT${index}=${stop}" | sudo tee -a "${config_file}" > /dev/null
    fi
  done

  # Restart TLP only if it is enabled
  local query='.[] | select(.unit == "tlp.service")'

  local tlp_process=''
  tlp_process="$(systemctl -a | jc --systemctl | jq -cr "${query}")" || return 1

  if is_not_empty "${tlp_process}"; then
    sudo systemctl restart tlp.service &> /dev/null || return 1
  fi

  log "Charging set to start at ${start}% and stop at ${stop}%."
}

# Shuts the system power down.
shutdown_system () {
  systemctl poweroff

  if has_failed; then
    log 'Failed to shutdown the system.'
    return 2
  fi
}

# Reboots the system.
reboot_system () {
  systemctl reboot

  if has_failed; then
    log 'Failed to reboot the system.'
    return 2
  fi
}

# Sets system in suspend mode.
suspend_system () {
  systemctl suspend

  if has_failed; then
    log 'Failed to suspend the system.'
    return 2
  fi
}

# Blanks the screen immediately.
blank_screen () {
  xset dpms force off

  if has_failed; then
    log 'Failed to blank the screen.'
    return 2
  fi
}
