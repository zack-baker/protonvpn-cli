#!/usr/bin/env bash
######################################################
# ProtonVPN CLI
# ProtonVPN Command-Line Tool
#
# Made with <3 for Linux + MacOS.
###
#Author: Mazin Ahmed <Mazin AT ProtonMail DOT ch>
######################################################

#Moved functions above to define them before use

function help_message() {
    echo "ProtonVPN Command-Line Tool"
    echo -e "\tUsage:"
    echo "$0 -init, --init                   Initialize ProtonVPN profile on the machine."
    echo "$0 -c, -connect                    Select a VPN from ProtonVPN menu."
    echo "$0 -random-connect                 Connect to a random ProtonVPN VPN."
    echo "$0 -fastest-connect                Connected to a fast ProtonVPN VPN."
    echo "$0 -d, disconnect, -disconnect     Disconnect from VPN."
    echo "$0 -ip                             Print the current public IP address."
    echo "$0 -install                        Install protonvpn-cli."
    echo "$0 -uninstall                      Uninstall protonvn-cli."
    echo "$0 -h, --help                      Show help message."
    exit 0
}

function check_ip() {
  counter=0
  ip=""
  while [[ "$ip" == "" ]]; do
    if [[ $counter -gt 0 ]]; then
      sleep 2
    fi

    if [[ $counter -lt 3 ]]; then
      ip=$(wget --header 'x-pm-appversion: Other' --header 'x-pm-apiversion: 3' \
        --header 'Accept: application/vnd.protonmail.v1+json' \
        --timeout 4 -q -O /dev/stdout 'https://api.protonmail.ch/vpn/location' \
        | grep 'IP' | cut -d ':' -f2 | cut -d '"' -f2)
      counter=$((counter+1))
    else
      ip="Error."
    fi
  done
  echo "$ip"
}

#if the first argument is empty, or it's one of '-h', '--help', '-help', '--h', or 'help', call help_message (no need for sudo)
if [[ -z "$1" || ( ("$1" == "-h") || ("$1" == "--help") || ("$1" == "-help") || ("$1" == "--h") || ("$1" == "help") ) ]]; then
  help_message
fi

#if the first argument is 'ip', '-ip', or '--ip', print ip info (no need for sudo)
if [[ ( ("$1" == "ip") || ("$1" == "-ip") || ("$1" == "--ip") ) ]]; then
  check_ip
  exit 0
fi

#For all other commands, the user must be root to access, so exit if not root.
if [[ ("$UID" != 0) ]]; then
  echo "[!] Error: The program requires root access."
  exit 1
fi

function check_requirements() {
  if [[ $(which openvpn) == "" ]]; then
    echo "[!] Error: openvpn is not installed. Install \`openvpn\` package to continue."
    exit 1
  fi
  if [[ $(which python) == "" ]]; then
    echo "[!] Error: python is not installed. Install \`python\` package to continue."
    exit 1
  fi
  if [[ $(which dialog) == "" ]]; then
    echo "[!] Error: dialog is not installed. Install \`dialog\` package to continue."
    exit 1
  fi
  if [[ $(which wget) == "" ]]; then
    echo "[!] Error: wget is not installed. Install \`wget\` package to continue."
    exit 1
  fi

  if [[ $(which sysctl) == "" ]]; then
    echo "[!] Error: sysctl is not installed. Install \`sysctl\` package to continue."
    exit 1
  fi
}



function init_cli() {
  rm -rf ~/.protonvpn-cli/  # Previous profile will be removed/overwritten, if any.
  mkdir -p ~/.protonvpn-cli/

  read -p "Enter OpenVPN username: " "openvpn_username"
  read -s -p "Enter OpenVPN password: " "openvpn_password"
  echo -e "$openvpn_username\n$openvpn_password" > ~/.protonvpn-cli/protonvpn_openvpn_credentials
  chown "$USER:$(id -gn $USER)" ~/.protonvpn-cli/protonvpn_openvpn_credentials
  chmod 0400 ~/.protonvpn-cli/protonvpn_openvpn_credentials

  echo -e "\n[.] ProtonVPN Plans:\n1) Free\n2) Basic\n3) Plus\n4) Visionary"
  protonvpn_tier=""
  available_plans=(1 2 3 4)
  while [[ $protonvpn_tier == "" ]]; do
    read -p "Enter Your ProtonVPN plan ID: " "protonvpn_plan"
    case "${available_plans[@]}" in  *"$protonvpn_plan"*)
      protonvpn_tier=$((protonvpn_plan-1))
      ;;
    4)
      protonvpn_tier=$((protonvpn_tier-1)) # Visionary gives access to the same VPNs as Plus.
      ;;
    *)
      echo "Invalid input."
    ;; esac
  done
  echo -e "$protonvpn_tier" > ~/.protonvpn-cli/protonvpn_tier
  chown "$USER:$(id -gn $USER)" ~/.protonvpn-cli/protonvpn_tier
  chmod 0400 ~/.protonvpn-cli/protonvpn_tier

  chown "$USER:$(id -gn $USER)" -R ~/.protonvpn-cli/
  chmod -R 0400 ~/.protonvpn-cli/

}

function manage_ipv6() {
  # ProtonVPN support for IPv6 coming soon.
  if [[ "$1" == "disable" ]]; then
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null
  fi

  if [[ "$1" == "enable" ]]; then
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null
  fi
}

function modify_dns_resolvconf() {

  if [[ "$1" == "backup_resolvconf" ]]; then
    cp "/etc/resolv.conf" "/etc/resolv.conf.protonvpn_backup" # backing-up current resolv.conf
  fi

  if [[ "$1" == "to_protonvpn_dns" ]]; then
    if [[ $(cat ~/.protonvpn-cli/protonvpn_tier) == "0" ]]; then
      dns_server="10.8.0.1" # free tier dns
    else
      dns_server="10.8.8.1" # paid tier dns
    echo -e "# ProtonVPN DNS - protonvpn-cli\nnameserver $dns_server" > "/etc/resolv.conf"
    fi
  fi

  if [[ "$1" == "revert_to_backup" ]]; then
    cp "/etc/resolv.conf.protonvpn_backup" "/etc/resolv.conf"
  fi
}

function is_openvpn_currently_running() {
  if [[ $(pgrep openvpn) == "" ]]; then
    echo false
  else
    echo true
  fi
}

function openvpn_disconnect() {
  max_checks=3
  counter=0

  if [[ "$1" != "quiet" ]]; then
    echo "Disconnecting..."
  fi

  while [[ $counter -lt $max_checks ]]; do
      pkill -f openvpn
      sleep 0.50
      if [[ $(is_openvpn_currently_running) == false ]]; then
        modify_dns_resolvconf revert_to_backup # Reverting to original resolv.conf
        manage_ipv6 enable # Enabling IPv6 on machine.
        if [[ "$1" != "quiet" ]]; then
          echo "[#] Disconnected."
          echo "[#] Current IP: $(check_ip)"
        fi
        exit 0
      fi
    counter=$((counter+1))
  done
  if [[ "$1" != "quiet" ]]; then
    echo "[!] Error disconnecting OpenVPN."
    exit 1
  fi
}

function openvpn_connect() {
  if [[ $(is_openvpn_currently_running) == true ]]; then
    echo "[!] Error: OpenVPN is already running on this machine."
    exit 1
  fi
  modify_dns_resolvconf backup_resolvconf # backuping-up current resolv.conf

  config_id=$1
  selected_protocol=$2
  if [[ $selected_protocol == "" ]]; then
    selected_protocol="udp"  # Default protocol
  fi

  current_ip=$(check_ip)

  wget --header 'x-pm-appversion: Other' --header 'x-pm-apiversion: 3' \
    --header 'Accept: application/vnd.protonmail.v1+json' \
    --timeout 4 -q -O /dev/stdout "https://api.protonmail.ch/vpn/config?Platform=linux&ServerID=$config_id&Protocol=$selected_protocol" \
    | openvpn --daemon --config "/dev/stdin" --auth-user-pass ~/.protonvpn-cli/protonvpn_openvpn_credentials --auth-nocache

  echo "Connecting..."

  max_checks=3
  counter=0
  while [[ $counter -lt $max_checks ]]; do
    sleep 5
    new_ip=$(check_ip)
    if [[ ("$current_ip" != "$new_ip") && ("$new_ip" != "Error.") ]]; then
      modify_dns_resolvconf to_protonvpn_dns # Use protonvpn DNS server
      manage_ipv6 disable # Disabling IPv6 on machine.

      echo "[$] Connected!"
      echo "[#] New IP: $new_ip"
      exit 0
    fi

    counter=$((counter+1))
  done
  echo "[!] Error connecting to VPN."
  openvpn_disconnect quiet
  exit 1
}

function install_cli() {
  mkdir -p "/usr/local/bin/"
  cli="$( cd "$(dirname "$0")" ; pwd -P )/$0"
  cp "$cli" "/usr/local/bin/protonvpn-cli"
  ln -s -f "/usr/local/bin/protonvpn-cli" "/usr/local/bin/pvpn"
  chown "$USER:$(id -gn $USER)" "/usr/local/bin/protonvpn-cli" "/usr/local/bin/pvpn"
  chmod 0755 "/usr/local/bin/protonvpn-cli" "/usr/local/bin/pvpn"
  echo "Done."
}

function uninstall_cli() {
  rm -f "/usr/local/bin/protonvpn-cli" "/usr/local/bin/pvpn"
  rm -rf ~/.protonvpn-cli/
  echo "Done."
}

function check_if_profile_initialized() {
  _=$(cat ~/.protonvpn-cli/protonvpn_openvpn_credentials ~/.protonvpn-cli/protonvpn_tier &> /dev/null)
  if [[ $? != 0 ]]; then
    echo "[!] Profile is not initialized."
    echo -e "Initialize your profile using: \n    $0 -init"
    exit 1
  fi
}

function connect_to_fastest_vpn() {
  check_if_profile_initialized
  if [[ $(is_openvpn_currently_running) == true ]]; then
    echo "[!] Error: OpenVPN is already running on this machine."
    exit 1
  fi
  if [[ $(check_ip) == "Error." ]]; then
    echo "[!]Error: There is an internet connection issue."
    exit 1
  fi

  echo "Fetching ProtonVPN Servers..."
  config_id=$(get_fastest_vpn_connection_id)
  selected_protocol="udp"
  openvpn_connect "$config_id" "$selected_protocol"
}

function connect_to_random_vpn() {
  check_if_profile_initialized
  if [[ $(is_openvpn_currently_running) == true ]]; then
    echo "[!] Error: OpenVPN is already running on this machine."
    exit 1
  fi
  if [[ $(check_ip) == "Error." ]]; then
    echo "[!]Error: There is an internet connection issue."
    exit 1
  fi

  echo "Fetching ProtonVPN Servers..."
  config_id=$(get_fastest_vpn_connection_id)
  available_protocols=("tcp" "udp")
  selected_protocol=${available_protocols[$RANDOM % ${#available_protocols[@]}]}
  openvpn_connect "$config_id" "$selected_protocol"
}

function connection_to_vpn_via_dialog_menu() {
  check_if_profile_initialized
  if [[ $(is_openvpn_currently_running) == true ]]; then
    echo "[!] Error: OpenVPN is already running on this machine."
    exit 1
  fi
  if [[ $(check_ip) == "Error." ]]; then
    echo "[!]Error: There is an internet connection issue."
    exit 1
  fi

  available_protocols=("udp" " " "tcp" " ")
  IFS=$'\n'
  ARRAY=()

  echo "Fetching ProtonVPN Servers..."

  c2=$(get_vpn_config_details)
  counter=0
  for i in $c2; do
    ID=$(echo "$i" | cut -d " " -f1)
    data=$(echo "$i" | tr '@' ' ' | awk '{$1=""; print $0}' | tr ' ' '@')
    counter=$((counter+1))
    ARRAY+=($counter)
    ARRAY+=($data)
  done

  config_id=$(dialog --clear  --ascii-lines --output-fd 1 --title "ProtonVPN-CLI" --column-separator "@" \
    --menu "ID - Name - Country - Load - EntryIP - ExitIP - Features" 35 300 "$((${#ARRAY[@]}))" "${ARRAY[@]}" )
  clear
  if [[ $config_id == "" ]]; then
    exit 2
  fi

  c=1
  for i in $c2; do
    ID=$(echo "$i" | cut -d " " -f1)
    if [[ $c -eq $config_id ]]; then
      ID=$(echo "$i" | cut -d " " -f1)
      config_id=$ID
      break
    fi
    c=$((c+1))
  done

  selected_protocol=$(dialog --clear  --ascii-lines --output-fd 1 --title "ProtonVPN-CLI" \
    --menu "Select Network Protocol" 35 80 2 "${available_protocols[@]}")
  clear
  if [[ $selected_protocol == "" ]]; then
    exit 2
  fi

  openvpn_connect "$config_id" "$selected_protocol"

}
function get_fastest_vpn_connection_id() {
  response_output=$(wget --header 'x-pm-appversion: Other' --header 'x-pm-apiversion: 3' \
    --header 'Accept: application/vnd.protonmail.v1+json' \
    --timeout 20 -q -O /dev/stdout "https://api.protonmail.ch/vpn/logicals")
  tier=$(cat ~/.protonvpn-cli/protonvpn_tier)
  output=`python <<END
import json, random
json_parsed_response = json.loads("""$response_output""")
min_load = json_parsed_response["LogicalServers"][0]
candidates1 = []
candidates2 = []
all_features = {"SECURE_CORE": 1, "TOR": 2, "P2P": 4, "XOR": 8, "IPV6": 16}
excluded_features_on_fastest_connect = ["TOR"]

for _ in json_parsed_response["LogicalServers"]:
    server_features_index = int(_["Features"])
    server_features  = []
    for f in all_features.keys():
        if (server_features_index & all_features[f]) > 0:
            server_features.append(f)
    is_excluded = False
    for excluded_feature in excluded_features_on_fastest_connect:
        if excluded_feature in server_features:
            is_excluded = True
    if is_excluded is True:
        continue
    if (_["Load"] < min_load["Load"]) and (_["Load"] < 10) and (_["Tier"] <= int("""$tier""")):
        min_load = _
        candidates1.append(_)
min_score = candidates1[0]
for _ in candidates1:
    if (_["Score"] < min_score["Score"]):
        candidates2.append(_)
if len(candidates2) == 0:
    vpn_connection_id = random.choice(candidates1)["Servers"][0]["ID"]
else:
    vpn_connection_id = random.choice(candidates2)["Servers"][0]["ID"]
print(vpn_connection_id)
END`

  echo "$output"
}

function get_random_vpn_connection_id() {
  response_output=$(wget --header 'x-pm-appversion: Other' --header 'x-pm-apiversion: 3' \
    --header 'Accept: application/vnd.protonmail.v1+json' \
    --timeout 20 -q -O /dev/stdout "https://api.protonmail.ch/vpn/logicals")
  tier=$(cat ~/.protonvpn-cli/protonvpn_tier)
  output=`python <<END
import json, random
json_parsed_response = json.loads("""$response_output""")
output = []
for _ in json_parsed_response["LogicalServers"]:
    if (_["Tier"] <= int("""$tier"""):
        output.append(_)
print(random.choice(output)["Servers"][0]["ID"])
END`

  echo "$output"
}

function get_vpn_config_details() {
  response_output=$(wget --header 'x-pm-appversion: Other' --header 'x-pm-apiversion: 3' \
    --header 'Accept: application/vnd.protonmail.v1+json' \
    --timeout 20 -q -O /dev/stdout "https://api.protonmail.ch/vpn/logicals")
  tier=$(cat ~/.protonvpn-cli/protonvpn_tier)
  output=`python <<END
import json, random
json_parsed_response = json.loads("""$response_output""")
output = []
for _ in json_parsed_response["LogicalServers"]:
    if (_["Tier"] <= int("""$tier""")):
        output.append(_)
all_features = {"SECURE_CORE": 1, "TOR": 2, "P2P": 4, "XOR": 8, "IPV6": 16}
for _ in output:
    server_features_index = int(_["Features"])
    server_features  = []
    server_features_output = ""
    for f in all_features.keys():
        if (server_features_index & all_features[f]) > 0:
            server_features.append(f)
    if len(server_features) == 0:
        server_features_output = "None"
    else:
        server_features_output = ",".join(server_features)

    o = "{} {}@{}@{}@{}@{}@{}".format(_["Servers"][0]["ID"], _["Name"], \
      _["EntryCountry"], _["Load"], _["Servers"][0]["EntryIP"], _["Servers"][0]["ExitIP"], \
      str(server_features_output))
    print(o)
END`

  echo "$output"
}



check_requirements
user_input=$1
case $user_input in
  ""|"-h"|"--help"|"--h"|"-help"|"help") help_message
    ;;
  "-d"|"-disconnect"|"--d"|"--disconnect") openvpn_disconnect
    ;;
  "-random-connect"|"-random"|"--random") connect_to_random_vpn
    ;;
  "-fastest-connect"|"-fastest"|"--fastest") connect_to_fastest_vpn
    ;;
  "-c"|"-connect"|"--c"|"--connect") connection_to_vpn_via_dialog_menu
    ;;
  "ip"|"-ip"|"--ip") check_ip
    ;;
  "-init"|"--init") init_cli
    ;;
  "-install"|"--install") install_cli
    ;;
  "-uninstall"|"--uninstall") uninstall_cli
    ;;
  *)
  echo "[!] Invalid input: $user_input"
  help_message
    ;;
esac
exit 0
