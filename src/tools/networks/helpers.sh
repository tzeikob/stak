#!/bin/bash

set -o pipefail

source /opt/stack/commons/input.sh
source /opt/stack/commons/error.sh
source /opt/stack/commons/logger.sh
source /opt/stack/commons/json.sh
source /opt/stack/commons/math.sh
source /opt/stack/commons/validators.sh

CONFIG_HOME="${HOME}/.config/stack"
NETWORKS_SETTINGS="${CONFIG_HOME}/networks.json"

# Returns the general status of the networking.
# Outputs:
#  A json object of status.
find_status () {
  nmcli general | jc --nmcli | jq -cer '.[0]' || return 1
}

# Returns the list of network devices of the
# given type.
# Arguments:
#  type: ethernet, wifi or bridge
# Outputs:
#  A json array of device objects.
find_devices () {
  local type="${1}"

  local query='.'

  if is_given "${type}"; then
    query="[.[]|select(.type == \"${type}\")]"
  fi

  nmcli device | jc --nmcli | jq -cer "${query}" || return 1
}

# Returns the device with the given name.
# Arguments:
#  name: the name of a device
# Outputs:
#  A josn object of a device.
find_device () {
  local name="${1}"

  local device=''
  device="$(nmcli device show "${name}" | jc --nmcli | jq -cer '.[0]')" || return 1

  local type=''
  type="$(get_property "${device}" ".type")" || return 1

  if equals "${type}" 'wifi'; then
    local query=''
    query+='freq: .frequency,'
    query+='rate: .bit_rate,'
    query+='quality: .link_quality,'
    query+='signal: .signal_level'
    query="if (.|length>0 and .[0].frequency) then .[0]|{${query}} else {} end"

    device="$(iwconfig "${name}" 2> /dev/null | jc --iwconfig |
      jq -cer --argjson d "${device}" "${query} + \$d")" || return 1
  fi

  echo "${device}"
}

# Returns the list of network connections.
# Outputs:
#  A json array of connection objects.
find_connections () {
  nmcli connection | jc --nmcli || return 1
}

# Returns the connection with the given name.
# Arguments:
#  name: the name of a connection
# Outputs:
#  A json object of connection.
find_connection () {
  local name="${1}"

  local connection=''
  connection="$(nmcli connection show "${name}" | jc --nmcli | jq -cer '.[0]')" || return 1

  local type=''
  type="$(get_property "${connection}" ".connection_type")" || return 1

  if equals "${type}" 'wireless'; then
    local device=''
    device="$(get_property "${connection}" ".connection_interface_name")" || return 1

    local query=''
    query+='freq: .frequency,'
    query+='rate: .bit_rate,'
    query+='quality: .link_quality,'
    query+='signal: .signal_level'
    query="if (.|length>0 and .[0].frequency) then .[0]|{${query}} else {} end"

    if is_network_device "${device}"; then
      connection="$(iwconfig "${device}" 2> /dev/null | jc --iwconfig |
        jq -cer --argjson c "${connection}" "${query} + \$c")" || return 1
    fi
  fi
  
  echo "${connection}"
}

# Returns any detected wifi networks broadcasting in
# your local area having a singal strength equal or
# greater to the given value.
# Arguments:
#  device: the name of a wifi device
#  signal: a signal limitation value
# Outputs:
#  A json array list of wifi networks.
find_wifis () {
  local device="${1}"
  local signal="${2:-"0"}"

  local networks=''
  networks="$(nmcli -f SSID,SIGNAL,CHAN,SECURITY -t device wifi list ifname "${device}" |
    awk -v limit="${signal}" -F: '{
      if ($2 >= limit) {
        schema="\"ssid\":\"%s\","
        schema=schema"\"signal\":%s,"
        schema=schema"\"channel\":\"%s\","
        schema=schema"\"security\":\"%s\""
        schema="{"schema"},"
        printf schema, $1,$2,$3,$4,$5
      }
    }'
  )" || return 1

  # Remove the last comma after the last element
  networks="${networks:+${networks::-1}}"

  echo "[${networks}]"
}

# Validates if the network device with the given name
# exists and is a valid networking entity.
# Arguments:
#  name: the name of the device
#  type: ethernet, wifi or bridge
# Returns:
#  0 if device is valid otherwise 1.
is_network_device () {
  local name="${1}"
  local type="${2}"

  local query=".[]|select(.device == \"${name}\")"

  if is_given "${type}"; then
    query+="|select(.type == \"${type}\")"
  fi

  local result=''
  result="$(find_devices | jq -cer "${query}")"

  if has_failed || is_empty "${result}"; then
    return 1
  fi
}

# An inverse version of is_network_device.
is_not_network_device () {
  is_network_device "${1}" "${2}" && return 1 || return 0
}

# Validates if the connection with the given name
# exists and is a valid networking entity.
# Arguments:
#  name: the name of the connection
# Returns:
#  0 if connection is valid otherwise 1.
is_connection () {
  local name="${1}"

  local result=''
  result="$(find_connections | jq -cer ".[]|select(.name == \"${name}\")")"

  if has_failed || is_empty "${result}"; then
    return 1
  fi
}

# An inverse version of is_connection.
is_not_connection () {
  is_connection "${1}" && return 1 || return 0
}

# Shows a menu asking the user to select one device.
# Arguments:
#  type: ethernet, wifi or bridge
# Outputs:
#  A menu of device names.
pick_device () {
  local type="${1}"

  local query='{key: .device, value: .device}'
  query="[.[]|${query}]"

  local devices=''
  devices="$(find_devices "${type}" | jq -cer "${query}")" || return 1

  local len=0
  len="$(get_property "${devices}" 'length')" || return 1

  if is_true "${len} = 0"; then
    log "No ${type:-network} devices found."
    return 2
  fi

  pick_one "Select ${type:-network} device name:" "${devices}" vertical || return $?
}

# Shows a menu asking the user to select one connection.
# Outputs:
#  A menu of connection names.
pick_connection () {
  local query='{key: .name, value: .name}'
  query="[.[]|${query}]"

  local connections=''
  connections="$(find_connections | jq -cer "${query}")" || return 1

  local len=0
  len="$(get_property "${connections}" 'length')" || return 1

  if is_true "${len} = 0"; then
    log 'No connections have found.'
    return 2
  fi

  pick_one 'Select connection name:' "${connections}" vertical || return $?
}

# Shows a menu asking the user to select one wifi network.
# Arguments:
#  device: the name of a wifi network device
# Outputs:
#  A menu of wifi ssids.
pick_wifi () {
  local device="${1}"

  log 'Detecting available wifi networks...'
  
  local networks=''
  networks="$(find_wifis "${device}")" || return 1

  local len=0
  len="$(get_property "${networks}" 'length')" || return 1

  if is_true "${len} = 0"; then
    log 'No wifi networks detected.'
    return 2
  fi

  local query='{key: .ssid, value: "[\(.signal)] \(.ssid)"}'
  query="[.[]|${query}]"

  networks="$(echo "${networks}" | jq -cer "${query}")" || return 1

  pick_one 'Select network ssid:' "${networks}" vertical || return $?
}

# Shows a menu asking the user to select one proxy profile.
# Outputs:
#  A menu of proxy profiles.
pick_proxy () {
  if file_not_exists "${NETWORKS_SETTINGS}"; then
    log 'No proxy profiles have found.'
    return 2
  fi

  local query=''
  query+='{key: .name, value: "\(.name) [\(.host)]"}'
  query=".proxies|if .|length>0 then [.[]|${query}] else [] end"

  local proxies=''
  proxies="$(jq -cer "${query}" "${NETWORKS_SETTINGS}")" || return 1
  
  local len=0
  len="$(get_property "${proxies}" 'length')" || return 1

  if is_true "${len} = 0"; then
    log 'No proxy profiles have found.'
    return 2
  fi

  pick_one 'Select proxy profile:' "${proxies}" vertical || return $?
}

# Saves the given proxy profile into settings.
# Arguments:
#  name:     the name of the proxy profile
#  host:     the host of the proxy server
#  port:     the port of the proxy server
#  username: the user name
#  password: the password
#  no_proxy: the hosts to ignore proxy
save_proxy_to_settings () {
  local name="${1}"
  local host="${2}"
  local port="${3}"
  local username="${4}"
  local password="${5}"
  local no_proxy="${6}"

  if is_given "${no_proxy}"; then
    local query='[split(",")|.[]|if . and .!="" then . else empty end]'
    no_proxy="$(echo "\"${no_proxy}\"" | jq -cer "${query}")" || return 1
  else
    no_proxy='[]'
  fi
  
  local proxy=''
  proxy+="\"name\": \"${name}\","
  proxy+="\"host\": \"${host}\","
  proxy+="\"port\": \"${port}\","
  proxy+="\"username\": \"${username}\","
  proxy+="\"password\": \"${password}\","
  proxy+="\"no_proxy\": ${no_proxy}"
  
  proxy="{${proxy}}"

  local settings='{}'

  if file_exists "${NETWORKS_SETTINGS}"; then
    settings="$(jq -e ".proxies += [${proxy}]" "${NETWORKS_SETTINGS}")" || return 1
  else
    settings="$(echo "{\"proxies\": [${proxy}]}" | jq -e '.')" || return 1
  fi

  mkdir -p "${CONFIG_HOME}"
  echo "${settings}" > "${NETWORKS_SETTINGS}"
}

# Checks if the proxy profile with the given name
# already exists in settings.
# Arguments:
#  name: the name of proxy profile
# Returns:
#  0 if exists otherwise 1.
exists_proxy_profile () {
  local name="${1}"

  if file_not_exists "${NETWORKS_SETTINGS}"; then
    return 1
  fi

  local query=''
  query+=".proxies|if . then .[]|select(.name == \"${name}\") else empty end"
  
  local proxy="$(jq -cr "${query}" "${NETWORKS_SETTINGS}")"

  if is_empty "${proxy}"; then
    return 1
  fi

  return 0
}

# Checks if the file with the given file path
# is a valid ovpn file.
# Arguments:
#  file_path: a file path
# Returns:
#  0 if file is valid ovpn file otherwise 1.
is_ovpn_file () {
  local file_path="${1}"
  
  local name=$(basename -- "${file_path}")
  local extension="${name##*.}"

  if not_equals "${extension}" 'ovpn'; then
    return 1
  fi

  return 0
}

# An inverse version of is_ovpn_file.
is_not_ovpn_file () {
  is_ovpn_file "${1}" && return 1 || return 0
}

