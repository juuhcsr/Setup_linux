#!/bin/sh -e
MY_COMMAND="$0 $*"
exit_trap() {
  # shellcheck disable=SC2181
  if [ $? -eq 0 ]; then
    return 0
  fi
  echo ""
  echo "An error occurred."
  echo "Try running in debug mode with 'sh -x ${MY_COMMAND}'"
  echo "Ask for help on https://github.com/cloudradar-monitoring/rport-pairing/discussions/categories/help-needed "
  echo ""
}
trap exit_trap EXIT

# BEGINNING of templates/header.txt ----------------------------------------------------------------------------------|

##
## This is the RPort client installer script.
## It helps you to quickly install the rport client on a variety of Linux distributions.
## The scripts creates a initial configuration and connects the client to your server.
##
## For any inquiries use our GitHub forum on
## https://github.com/cloudradar-monitoring/rport-pairing/discussions/
##
## Copyright cloudradar GmbH, Potsdam Germany, 2022
## Released under the MIT open-source license.
## https://github.com/cloudradar-monitoring/rport-pairing/blob/main/LICENSE
##
# END of templates/header.txt ----------------------------------------------------------------------------------------|

## BEGINNING of rendered template templates/linux/installer_vars.sh
#
# Dynamically inserted variables
#
FINGERPRINT="7c:0c:92:4f:a6:07:1f:53:d6:72:2d:45:b3:d1:ce:a9"
CONNECT_URL="http://rport.colaborativa.com.br:7891"
CLIENT_ID="clientAuth1"
PASSWORD="1234"

#
# Global static installer vars
#
TMP_FOLDER=/tmp/rport-install
FORCE=1
USE_ALTERNATIVE_MACHINEID=0
LOG_DIR=/var/log/rport
LOG_FILE=${LOG_DIR}/rport.log
## END of rendered template templates/linux/installer_vars.sh


# BEGINNING of templates/linux/vars.sh -------------------------------------------------------------------------------|

#
# Global Variables for installation and update
#
CONF_DIR=/etc/rport
CONFIG_FILE=${CONF_DIR}/rport.conf
USER=rport
ARCH=$(uname -m | sed s/"armv\(6\|7\)l"/'armv\1'/ | sed s/aarch64/arm64/)
# END of templates/linux/vars.sh -------------------------------------------------------------------------------------|


# BEGINNING of templates/linux/functions.sh --------------------------------------------------------------------------|

set -e
#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  is_available
#   DESCRIPTION:  Check if a command is available on the system.
#    PARAMETERS:  command name
#       RETURNS:  0 if available, 1 otherwise
#----------------------------------------------------------------------------------------------------------------------
is_available() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  uninstall
#   DESCRIPTION:  Uninstall everything and remove the user
#----------------------------------------------------------------------------------------------------------------------
uninstall() {
  if pgrep rportd >/dev/null; then
    echo 1>&2 "You are running the rportd server on this machine. Uninstall manually."
    exit 0
  fi
  systemctl stop rport >/dev/null 2>&1 || true
  rc-service rport stop >/dev/null 2>&1 || true
  pkill -9 rport >/dev/null 2>&1 || true
  rport --service uninstall >/dev/null 2>&1 || true
  FILES="/usr/local/bin/rport
    /usr/local/bin/rport
    /etc/systemd/system/rport.service
    /etc/sudoers.d/rport-update-status
    /etc/sudoers.d/rport-all-cmd
    /usr/local/bin/tacoscript
    /etc/init.d/rport
    /var/run/rport.pid
    /etc/runlevels/default/rport"
  for FILE in $FILES; do
    if [ -e "$FILE" ]; then
      rm -f "$FILE" && echo " [ DELETED ] File $FILE"
    fi
  done
  if id rport >/dev/null 2>&1; then
    if is_available deluser; then
      deluser --remove-home rport >/dev/null 2>&1 || true
      deluser --only-if-empty --group rport >/dev/null 2>&1 || true
    elif is_available userdel; then
      userdel -r -f rport >/dev/null 2>&1
    fi
    if is_available groupdel; then
      groupdel -f rport >/dev/null 2>&1 || true
    fi
    echo " [ DELETED ] User rport"
  fi
  FOLDERS="/etc/rport
    /var/log/rport
    /var/lib/rport"
  for FOLDER in $FOLDERS; do
    if [ -e "$FOLDER" ]; then
      rm -rf "$FOLDER" && echo " [ DELETED ] Folder $FOLDER"
    fi
  done
  echo "RPort client successfully uninstalled."
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  print_distro
#   DESCRIPTION:  print name of the distro
#----------------------------------------------------------------------------------------------------------------------
print_distro() {
  if [ -e /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release 2>/dev/null||true
    echo "Detected Linux Distribution: ${PRETTY_NAME}"
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  create_sudoers_all
#   DESCRIPTION:  create a sudoers file to grant full sudo right to the rport user
#----------------------------------------------------------------------------------------------------------------------
create_sudoers_all() {
  SUDOERS_FILE=/etc/sudoers.d/rport-all-cmd
  if [ -e "$SUDOERS_FILE" ]; then
    echo "You already have a $SUDOERS_FILE. Not changing."
    return 1
  fi

  if is_available sudo; then
    echo "#
# This file has been auto-generated during the installation of the rport client.
# Change to your needs or delete.
#
${USER} ALL=(ALL) NOPASSWD:ALL
" >$SUDOERS_FILE
    echo "A $SUDOERS_FILE has been created. Please review and change to your needs."
  else
    echo "You don't have sudo installed. No sudo rules created. RPort will not be able to get elevated right."
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  create_sudoers_updates
#   DESCRIPTION:  create a sudoers file to allow rport supervise the update status
#----------------------------------------------------------------------------------------------------------------------
create_sudoers_updates() {
  SUDOERS_FILE=/etc/sudoers.d/rport-update-status
  if [ -e "$SUDOERS_FILE" ]; then
    echo "You already have a $SUDOERS_FILE. Not changing."
    return 0
  fi

  if is_available sudo; then
    echo '#
# This file has been auto-generated during the installation of the rport client.
# Change to your needs.
#' >$SUDOERS_FILE
    if is_available apt-get; then
      echo "${USER} ALL=NOPASSWD: SETENV: /usr/bin/apt-get update -o Debug\:\:NoLocking=true" >>$SUDOERS_FILE
    fi
    #if is_available yum;then
    #  echo 'rport ALL=NOPASSWD: SETENV: /usr/bin/yum *'>>$SUDOERS_FILE
    #fi
    #if is_available dnf;then
    #  echo 'rport ALL=NOPASSWD: SETENV: /usr/bin/dnf *'>>$SUDOERS_FILE
    #fi
    if is_available zypper; then
      echo "${USER} ALL=NOPASSWD: SETENV: /usr/bin/zypper refresh *" >>$SUDOERS_FILE
    fi
    #if is_available apk;then
    #  echo 'rport ALL=NOPASSWD: SETENV: /sbin/apk *'>>$SUDOERS_FILE
    #fi
    echo "A $SUDOERS_FILE has been created. Please review and change to your needs."
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  abort
#   DESCRIPTION:  Exit the script with an error message.
#----------------------------------------------------------------------------------------------------------------------
abort() {
  echo >&2 "$1 Exit!"
  clean_up
  exit 1
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  confirm
#   DESCRIPTION:  Print a success message.
#----------------------------------------------------------------------------------------------------------------------
confirm() {
  echo "Success: $1"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  check_prerequisites
#   DESCRIPTION:  Check if prerequisites are fulfilled.
#----------------------------------------------------------------------------------------------------------------------

check_prerequisites() {
  if [ "$(id -u)" -ne 0 ]; then
    abort "Execute as root or use sudo."
  fi

  if command -v sed >/dev/null 2>&1; then
    true
  else
    abort "sed command missing. Make sure sed is in your path."
  fi

  if command -v tar >/dev/null 2>&1; then
    true
  else
    abort "tar command missing. Make sure tar is in your path."
  fi
}

is_terminal() {
  if echo "$TERM" | grep -q "^xterm"; then
    return 0
  else
    echo 1>&2 "You are not on a terminal. Please use command line switches to avoid interactive questions."
    return 1
  fi
}

update_tacoscript() {
  TACO_VERSION=$(/usr/local/bin/tacoscript --version | grep -o "Version:.*" | awk '{print $2}')
  cd /tmp
  test -e tacoscript.tar.gz && rm -f tacoscript.tar.gz
  curl -LSso tacoscript.tar.gz "https://download.rport.io/tacoscript/${RELEASE}/?arch=Linux_${ARCH}&gt=$TACO_VERSION"
  if tar xzf tacoscript.tar.gz 2>/dev/null; then
    echo ""
    echo "Updating Tacoscript from ${TACO_VERSION} to latest ${RELEASE} $(./tacoscript --version | grep -o "Version:.*")"
    mv -f /tmp/tacoscript /usr/local/bin/tacoscript
  else
    echo "Nothing to do. Tacoscript is on the latest version ${TACO_VERSION}."
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  install_tacoscript
#   DESCRIPTION:  install Tacoscript on Linux
#----------------------------------------------------------------------------------------------------------------------
install_tacoscript() {
  if [ -e /usr/local/bin/tacoscript ]; then
    echo "Tacoscript already installed. Checking for updates ..."
    update_tacoscript
    return 0
  fi
  cd /tmp
  test -e tacoscript.tar.gz && rm -f tacoscript.tar.gz
  curl -LJs "https://download.rport.io/tacoscript/${RELEASE}/?arch=Linux_${ARCH}" -o tacoscript.tar.gz
  tar xvzf tacoscript.tar.gz -C /usr/local/bin/ tacoscript
  rm -f tacoscript.tar.gz
  echo "Tacoscript installed $(/usr/local/bin/tacoscript --version)"
}

version_to_int() {
  echo "$1" |
    awk -v 'maxsections=3' -F'.' 'NF < maxsections {printf("%s",$0);for(i=NF;i<maxsections;i++)printf("%s",".0");printf("\n")} NF >= maxsections {print}' |
    awk -v 'maxdigits=3' -F'.' '{print $1*10^(maxdigits*2)+$2*10^(maxdigits)+$3}'
}

runs_with_selinux() {
  if command -v getenforce >/dev/null 2>&1 && getenforce | grep -q Enforcing; then
    return 0
  else
    return 1
  fi
}

enable_file_reception() {
  if [ "$(version_to_int "$TARGET_VERSION")" -lt 6005 ]; then
    # Version does not handle file reception yet.
    return 0
  fi
  if [ "$ENABLE_FILEREC" -eq 0 ]; then
    echo "File reception disabled."
    FILEREC_CONF="false"
  else
    echo "File reception enabled."
    FILEREC_CONF="true"
  fi
  if grep -q '\[file-reception\]' "$CONFIG_FILE"; then
    echo "File reception already configured"
  else
    cat <<EOF >>"$CONFIG_FILE"


[file-reception]
  ## Receive files pushed by the server, enabled by default
  # enabled = true
  ## The rport client will reject writing files to any of the following folders and its subfolders.
  ## https://oss.rport.io/docs/no18-file-reception.html
  ## Wildcards (glob) are supported.
  ## Linux defaults
  # protected = ['/bin', '/sbin', '/boot', '/usr/bin', '/usr/sbin', '/dev', '/lib*', '/run']
  ## Windows defaults
  # protected = ['C:\Windows\', 'C:\ProgramData']

EOF
  fi
  toml_set "$CONFIG_FILE" file-reception enabled $FILEREC_CONF
  # Clean up from pre-releases
  test -e /etc/sudoers.d/rport-filepush && rm -f /etc/sudoers.d/rport-filepush
  if [ "$ENABLE_FILEREC_SUDO" -eq 0 ]; then
    # File receptions sudo rules not desired, end this function here
    return 0
  fi
  # Create a sudoers file
  FILERCV_SUDO="/etc/sudoers.d/rport-filereception"
  if [ -e $FILERCV_SUDO ]; then
    echo "Sudo rule $FILERCV_SUDO already exists"
  else
    cat <<EOF >$FILERCV_SUDO
# The following rule allows the rport client to change the ownership of any file retrieved from the rport server
rport ALL=NOPASSWD: /usr/bin/chown * /var/lib/rport/filepush/*_rport_filepush

# The following rules allows the rport client to move copied files to any folder
rport ALL=NOPASSWD: /usr/bin/mv /var/lib/rport/filepush/*_rport_filepush *

EOF
  fi
}

enable_lan_monitoring() {
  if [ "$(version_to_int "$TARGET_VERSION")" -lt 5008 ]; then
    # Version does not handle network interfaces yet.
    return 0
  fi
  if grep "^\s*net_[wl]" "$CONFIG_FILE"; then
    # Network interfaces already configured
    return 0
  fi
  echo "Enabling Network monitoring"
  for IFACE in /sys/class/net/*; do
    IFACE=$(basename "${IFACE}")
    [ "$IFACE" = 'lo' ] && continue
    if ip addr show "$IFACE" | grep -E -q "inet (10|192\.168|172\.16)\."; then
      # Private IP
      NET_LAN="$IFACE"
    else
      # Public IP
      NET_WAN="$IFACE"
    fi
  done
  if [ -n "$NET_LAN" ]; then
    sed -i "/^\[monitoring\]/a \ \ net_lan = ['${NET_LAN}' , '1000' ]" "$CONFIG_FILE"
  fi
  if [ -n "$NET_WAN" ]; then
    sed -i "/^\[monitoring\]/a \ \ net_wan = ['${NET_WAN}' , '1000' ]" "$CONFIG_FILE"
  fi
}

detect_interpreters() {
  if [ "$(version_to_int "$TARGET_VERSION")" -lt 5008 ]; then
    # Version does not handle interpreters yet.
    return 0
  fi
  if grep -q "\[interpreter\-aliases\]" "$CONFIG_FILE"; then
    # Config already updated
    true
  else
    echo "Updating config with new interpreter-aliases ..."
    echo '[interpreter-aliases]' >>"$CONFIG_FILE"
  fi
  SEARCH="bash zsh ksh csh python3 python2 perl pwsh fish"
  for ITEM in $SEARCH; do
    FOUND=$(command -v "$ITEM" 2>/dev/null || true)
    if [ -z "$FOUND" ]; then
      continue
    fi
    echo "Interpreter '$ITEM' found in '$FOUND'"
    if grep -q -E "^\s*$ITEM =" "$CONFIG_FILE"; then
      echo "Interpreter '$ITEM' already registered."
      continue
    fi
    # Append the found interpreter to the config
    sed -i "/^\[interpreter-aliases\]/a \ \ $ITEM = \"$FOUND\"" "${CONFIG_FILE}"
  done
}

toml_set() {
  TOML_FILE="$1"
  BLOCK="$2"
  KEY="$3"
  VALUE="$4"
  if [ -w "$TOML_FILE" ];then
    true
  else
    2>&1 echo "$TOML_FILE does not exist or is not writable."
    return 1
  fi
  if grep -q "\[$BLOCK\]" "$TOML_FILE";then
    true
  else
    2>&1 echo "$TOML_FILE has no block [$BLOCK]"
    return 1
  fi
  LINE=$(grep -n -A100 "\[$BLOCK\]" "$TOML_FILE"|grep "${KEY} = ")
  if [ -z "$LINE" ];then
    2>&1 echo "Key $KEY not found in block $BLOCK"
    return 1
  fi
  LINE_NO=$(echo "$LINE"|cut -d'-' -f1)
  sed -i "${LINE_NO}s/.*/  ${KEY} = ${VALUE}/" "$TOML_FILE"
}
# END of templates/linux/functions.sh --------------------------------------------------------------------------------|


# BEGINNING of templates/linux/install.sh ----------------------------------------------------------------------------|

set -e
#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  prepare
#   DESCRIPTION:  Create a temporary folder and prepare the system to execute the installation
#----------------------------------------------------------------------------------------------------------------------
prepare() {
  test -e "${TMP_FOLDER}" && rm -rf "${TMP_FOLDER}"
  mkdir "${TMP_FOLDER}"
  cd "${TMP_FOLDER}"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  cleanup
#   DESCRIPTION:  Remove the temporary folder and cleanup any leftovers after script has ended
#----------------------------------------------------------------------------------------------------------------------
clean_up() {
  cd /tmp
  rm -rf "${TMP_FOLDER}"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  test_connection
#   DESCRIPTION:  Check if the RPort server is reachable or abort.
#----------------------------------------------------------------------------------------------------------------------
test_connection() {
  CONN_TEST=$(curl -vIs -m5 "${CONNECT_URL}" 2>&1||true)
  if echo "${CONN_TEST}"|grep -q "Connected to";then
    confirm "${CONNECT_URL} is reachable. All good."
  else
    echo "$CONN_TEST"
    echo ""
    echo "Testing the connection to the RPort server on ${CONNECT_URL} failed."
    echo "* Check your internet connection and firewall rules."
    echo "* Check if a transparent HTTP proxy is sniffing and blocking connections."
    echo "* Check if a virus scanner is inspecting HTTP connections."
    abort "FATAL: No connection to the RPort server."
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  download_and_extract
#   DESCRIPTION:  Download the package from Github and unpack to the temp folder
#                 https://downloads.rport.io/ acts a redirector service
#                 returning the real download URL of GitHub in a more handy fashion
#----------------------------------------------------------------------------------------------------------------------
download_and_extract() {
  cd "${TMP_FOLDER}"
  # Download the tar.gz package
  if is_available curl; then
    curl -LSs "https://downloads.rport.io/rport/${RELEASE}/latest.php?arch=Linux_${ARCH}" -o rport.tar.gz
  elif is_available wget; then
    wget -q "https://downloads.rport.io/rport/${RELEASE}/latest.php?arch=Linux_${ARCH}" -O rport.tar.gz
  else
    abort "No download tool found. Install curl or wget."
  fi
  # Unpack
  tar xzf rport.tar.gz
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  install_bin
#   DESCRIPTION:  Install a binary located in the temp folder to /usr/local/bin
#    PARAMETERS:  binary name relative to the temp folder
#----------------------------------------------------------------------------------------------------------------------
install_bin() {
  EXEC_BIN=/usr/local/bin/${1}
  if [ -e "$EXEC_BIN" ]; then
    if [ "$FORCE" -eq 0 ]; then
      abort "${EXEC_BIN} already exists. Use -f to overwrite."
    fi
  fi
  mv "${TMP_FOLDER}/${1}" "${EXEC_BIN}"
  confirm "${1} installed to ${EXEC_BIN}"
  TARGET_VERSION=$(${EXEC_BIN} --version |awk '{print $2}')
  confirm "RPort $TARGET_VERSION installed to $EXEC_BIN"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  install_config
#   DESCRIPTION:  Install an example config located in the temp folder to /etc/rport
#    PARAMETERS:  config name relative to the temp folder without suffix .example.conf
#----------------------------------------------------------------------------------------------------------------------
install_config() {
  test -e "$CONF_DIR" || mkdir "$CONF_DIR"
  CONFIG_FILE=${CONF_DIR}/${1}.conf
  if [ -e "${CONFIG_FILE}" ]; then
    mv "${CONFIG_FILE}" "${CONFIG_FILE}".bak
    confirm "Old config has been backed up to ${CONFIG_FILE}.bak"
  fi
  mv "${TMP_FOLDER}/rport.example.conf" "${CONFIG_FILE}"
  confirm "${CONFIG_FILE} created."
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  create_user
#   DESCRIPTION:  Create a system user "rport"
#----------------------------------------------------------------------------------------------------------------------
create_user() {
  confirm "RPort will run as user ${USER}"
  if id "${USER}" >/dev/null 2>&1; then
    confirm "User ${USER} already exist."
  else
    if is_available useradd; then
      useradd -r -d /var/lib/rport -m -s /bin/false -U -c "System user for rport client" $USER
    elif is_available adduser; then
      addgroup rport
      adduser -h /var/lib/rport -s /bin/false -G rport -S -D $USER
    else
      abort "No command found to add a user"
    fi
  fi
  test -e "$LOG_DIR" || mkdir -p "$LOG_DIR"
  test -e /var/lib/rport/scripts || mkdir -p /var/lib/rport/scripts
  chown "${USER}":root "$LOG_DIR"
  chown "${USER}":root /var/lib/rport/scripts
  chmod 0700 /var/lib/rport/scripts
  chown "${USER}":root "$CONFIG_FILE"
  chmod 0640 "$CONFIG_FILE"
  chown root:root /usr/local/bin/rport
  chmod 0755 /usr/local/bin/rport
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  create_systemd_service
#   DESCRIPTION:  Install a systemd service file
#----------------------------------------------------------------------------------------------------------------------
create_systemd_service() {
  echo "Installing systemd service for rport"
  test -e /etc/systemd/system/rport.service && rm -f /etc/systemd/system/rport.service
  /usr/local/bin/rport --service install --service-user "${USER}" --config /etc/rport/rport.conf
  if is_available systemctl; then
    systemctl daemon-reload
    systemctl start rport
    systemctl enable rport
  elif is_available service; then
    service rport start
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  create_openrc_service
#   DESCRIPTION:  Install a oprnrc service file
#----------------------------------------------------------------------------------------------------------------------
create_openrc_service() {
  echo "Installing openrc service for rport"
  cat << EOF >/etc/init.d/rport
#!/sbin/openrc-run
command="/usr/local/bin/rport"
command_args="-c /etc/rport/rport.conf"
command_user="${USER}"
command_background=true
pidfile=/var/run/rport.pid
EOF
  chmod 0755 /etc/init.d/rport
  rc-service rport start
  rc-update add rport default
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  prepare_server_cofnig
#   DESCRIPTION:  Make changes to the example config to give the user a better starting point
#----------------------------------------------------------------------------------------------------------------------
prepare_config() {
  echo "Preparing $CONFIG_FILE"
  sed -i "s|#*server = .*|server = \"${CONNECT_URL}\"|g" "$CONFIG_FILE"
  sed -i "s/#*auth = .*/auth = \"${CLIENT_ID}:${PASSWORD}\"/g" "$CONFIG_FILE"
  sed -i "s/#*fingerprint = .*/fingerprint = \"${FINGERPRINT}\"/g" "$CONFIG_FILE"
  sed -i "s/#*log_file = .*C.*Program Files.*/""/g" "$CONFIG_FILE"
  sed -i "s/#*log_file = /log_file = /g" "$CONFIG_FILE"
  sed -i "s|#updates_interval = '4h'|updates_interval = '4h'|g" "$CONFIG_FILE"
  if [ "$ENABLE_COMMANDS" -eq 1 ]; then
    sed -i "s/#allow = .*/allow = ['.*']/g" "$CONFIG_FILE"
    sed -i "s/#deny = .*/deny = []/g" "$CONFIG_FILE"
    sed -i '/^\[remote-scripts\]/a \ \ enabled = true' "$CONFIG_FILE"
    sed -i "s|# script_dir = '/var/lib/rport/scripts'|script_dir = '/var/lib/rport/scripts'|g" "$CONFIG_FILE"
  else
    sed -i '/^\[remote-commands\]/a \ \ enabled = false' "$CONFIG_FILE"
  fi

  # Set the hostname.
  if grep -Eq "\s+use_hostname = true" "$CONFIG_FILE";then
    # For versions >= 0.5.9
    # Just insert an example.
    sed -i "s/#name = .*/#name = \"$(get_hostname)\"/g" "$CONFIG_FILE"
  else
    # Older versions
    # Insert a hardcoded name
    sed -i "s/#*name = .*/name = \"$(get_hostname)\"/g" "$CONFIG_FILE"
  fi

  # Set the machine_id
  if grep -Eq "\s+use_system_id = true" "$CONFIG_FILE" && [ -e /etc/machine-id ];then
    # Versions >= 0.5.9 read it dynamically
    echo "Using /etc/machine-id as rport client id"
  else
    # Older versions need a hard coded id
    sed -i "s/#id = .*/id = \"$(machine_id)\"/g" "$CONFIG_FILE"
  fi

  if get_geodata; then
    if [ -n "$TAGS" ];then
      TAGS=$(printf "%s:%s:%s" "$TAGS" "$COUNTRY" "$CITY")
    else
      TAGS=$(printf "%s:%s" "$COUNTRY" "$CITY")
    fi
  fi
  if [ -n "$TAGS" ];then
    # shellcheck disable=SC2001
    TAGS='["'$(echo "$TAGS"|sed s/":"/\",\"/g)'"]'
    sed -i "s/#tags = .*/tags = ${TAGS}/g" "$CONFIG_FILE"
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  get_hostname
#   DESCRIPTION:  Try to get the hostname from various sources
#----------------------------------------------------------------------------------------------------------------------
get_hostname() {
  hostname -f 2>/dev/null && return 0
  hostname 2>/dev/null && return 0
  cat /etc/hostname 2>/dev/null && return 0
  LANG=en hostnamectl | grep hostname | grep -v 'n/a' |cut -d':' -f2 | tr -d ' '
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  machine_id
#   DESCRIPTION:  Try to get a unique machine id form different locations.
#                 Generate one based on the hostname as a fallback.
#----------------------------------------------------------------------------------------------------------------------
machine_id() {
  if [ -e /etc/machine-id ]; then
    cat /etc/machine-id
    return 0
  fi

  if [ -e /var/lib/dbus/machine-id ]; then
    cat /var/lib/dbus/machine-id
    return 0
  fi

  alt_machine_id
}

alt_machine_id() {
  ip a | grep ether | md5sum | awk '{print $1}'
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  install_client
#   DESCRIPTION:  Execute all needed steps to install the rport client
#----------------------------------------------------------------------------------------------------------------------
install_client() {
  echo "Installing rport client"
  print_distro
  if runs_with_selinux && [ "$SELINUX_FORCE" -ne 1 ];then
    echo ""
    echo "Your system has SELinux enabled. This installer will not create the needed policies."
    echo "Rport will not connect with out the right policies."
    echo "Read more https://kb.rport.io/digging-deeper/advanced-client-management/run-with-selinux"
    echo "Excute '$0 ${RAW_ARGS} -l' to skip this warning and install anyways. You must create the polcies later."
    exit 1
  fi
  test_connection
  download_and_extract
  install_bin rport
  install_config rport
  prepare_config
  enable_lan_monitoring
  detect_interpreters
  create_user
  if is_available openrc; then
    create_openrc_service
  else
    create_systemd_service
  fi
  create_sudoers_updates
  [ "$ENABLE_SUDO" -eq 1 ] && create_sudoers_all
  [ "$INSTALL_TACO" -eq 1 ] && install_tacoscript
  verify_and_terminate
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  verify_and_terminate
#   DESCRIPTION:  Verify the installation has succeeded
#----------------------------------------------------------------------------------------------------------------------
verify_and_terminate() {
  sleep 1
  if pgrep rport >/dev/null 2>&1; then
    if check_log; then
      finish
      return 0
    elif [ $? -eq 1 ] && [ "$USE_ALTERNATIVE_MACHINEID" -ne 1 ]; then
      USE_ALTERNATIVE_MACHINEID=1
      use_alternative_machineid
      verify_and_terminate
      return 0
    fi
  fi
  fail
}

use_alternative_machineid() {
  # If the /etc/machine-id is already used, use an alternative unique id
  systemctl stop rport
  rm -f "$LOG_FILE"
  echo "Creating a unique id based on the mac addresses of the network cards."
  sed -i "s/^id = .*/id = \"$(alt_machine_id)\"/g" "$CONFIG_FILE"
  systemctl start rport
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  get_geodata
#   DESCRIPTION:  Retrieve the Country and the city of the currently used public IP address
#----------------------------------------------------------------------------------------------------------------------
get_geodata() {
  GEODATA=""
  GEOSERVICE_URL="http://ip-api.com/line/?fields=status,country,city"
  if is_available curl; then
    GEODATA=$(curl -m2 -Ss "${GEOSERVICE_URL}" 2>/dev/null)
  else
    GEODATA=$(wget --timeout=2 -O - -q "${GEOSERVICE_URL}" 2>/dev/null)
  fi
  if echo "$GEODATA" | grep -q "^success"; then
    CITY="$(echo "$GEODATA" | head -n3 | tail -n1)"
    COUNTRY="$(echo "$GEODATA" | head -n2 | tail -n1)"
    GEODATA="1"
    return 0
  else
    return 1
  fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  check_log
#   DESCRIPTION:  Check the log file for proper operation or common errors
#----------------------------------------------------------------------------------------------------------------------
check_log() {
  if [ -e "$LOG_FILE" ];then
    true
  else
    echo 2>&1 "[!] Logfile $LOG_FILE does not exist."
    echo 2>&1 "[!] RPOrt very likely failed to start."
    return 4
  fi
  if grep -q "client id .* is already in use" "$LOG_FILE"; then
    echo ""
    echo 2>&1 "[!] Configuration error: client id is already in use."
    echo 2>&1 "[!] Likely you have systems with an duplicated machine-id in your network."
    echo ""
    return 1
  elif grep -q "Connection error: websocket: bad handshake" "$LOG_FILE"; then
    echo ""
    echo 2>&1 "[!] Connection error: websocket: bad handshake"
    echo "Check if transparent proxies are interfering outgoing http connections."
    return 2
  elif tac "$LOG_FILE" | grep error; then
    return 3
  fi

  return 0
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  help
#   DESCRIPTION:  print a help message and exit
#----------------------------------------------------------------------------------------------------------------------
help() {
  cat <<EOF
Usage $0 [OPTION(s)]

Options:
-h  Print this help message.
-f  Force  overwriting existing files and configurations.
-t  Use the latest unstable version (DANGEROUS!).
-u  Uninstall the rport client and all configurations and logs.
-x  Enable unrestricted command execution in rport.conf.
-s  Create sudo rules to grant full root access to the rport user.
-r  Enable file reception. (sending files from server to client)
-b  Create sudo rule for file reception to give full filesystem write access. Requires -r.
-a  <USER> Use a different user account than 'rport'. Will be created if not present.
-i  Install Tacoscript along with the RPort client.
-l  Install with SELinux enabled.
-g <TAG> Add an extra tag to the client.

Learn more https://kb.rport.io/connecting-clients#advanced-pairing-options
EOF
  exit 0
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  finish
#   DESCRIPTION:  print some information
#----------------------------------------------------------------------------------------------------------------------
finish() {
  echo "
#
#  Installation of rport finished.
#
#  This client is now connected to $SERVER
#
#  Look at $CONFIG_FILE and explore all options.
#  Logs are written to /var/log/rport/rport.log.
#
#  READ THE DOCS ON https://kb.rport.io/
#
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#  Give us a star on https://github.com/cloudradar-monitoring/rport
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#

Thanks for using
  _____  _____           _
 |  __ \|  __ \         | |
 | |__) | |__) |__  _ __| |_
 |  _  /|  ___/ _ \| '__| __|
 | | \ \| |  | (_) | |  | |_
 |_|  \_\_|   \___/|_|   \__|
"
}

fail() {
  echo "
#
# -------------!!   ERROR  !!-------------
#
# Installation of rport finished with errors.
#

Try the following to investigate:
1) systemctl rport status

2) tail /var/log/rport/rport.log

3) Ask for help on https://kb.rport.io/need-help/request-support
"
  if runs_with_selinux; then
    echo "
4) Check your SELinux settings and create a policy for rport."
  fi
}

#----------------------------------------------------------------------------------------------------------------------
#                                               END OF FUNCTION DECLARATION
#----------------------------------------------------------------------------------------------------------------------

#
# Check for prerequisites
#
check_prerequisites

MANDATORY="SERVER FINGERPRINT CLIENT_ID PASSWORD"
for VAR in $MANDATORY; do
  if eval "[ -z $${VAR} ]"; then
    abort "Variable \$${VAR} not set."
  fi
done

#
# Read the command line options and map to a function call
#
RAW_ARGS=$*
ACTION=install_client
ENABLE_COMMANDS=0
ENABLE_SUDO=0
RELEASE=stable
INSTALL_TACO=0
SELINUX_FORCE=0
ENABLE_FILEREC=0
ENABLE_FILEREC_SUDO=0
TAGS=""
while getopts 'hvfcsuxstilrba:g:' opt; do
  case "${opt}" in

  h) help ; exit 0 ;;
  f) FORCE=1 ;;
  v)
    echo "$0 -- Version $VERSION"
    exit 0
    ;;
  c) ACTION=install_client ;;
  u) ACTION=uninstall ;;
  x) ENABLE_COMMANDS=1 ;;
  s) ENABLE_SUDO=1 ;;
  t) RELEASE=unstable ;;
  i) INSTALL_TACO=1;;
  l) SELINUX_FORCE=1;;
  r) ENABLE_FILEREC=1;;
  b) ENABLE_FILEREC_SUDO=1;;
  a) USER=${OPTARG} ;;
  g) TAGS=${OPTARG} ;;

  \?)
    echo "Option does not exist."
    exit 1
    ;;
  esac # --- end of case ---
done
shift $((OPTIND - 1))
prepare  # Prepare the system
$ACTION  # Execute the function according to the users decision
clean_up # Clean up the system

# END of templates/linux/install.sh ----------------------------------------------------------------------------------|

