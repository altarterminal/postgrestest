#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

THIS_DIR=$(dirname "$(realpath "$0")")

print_usage_and_exit() {
  cat <<-USAGE 1>&2
Usage   : ${0##*/}
Options : -k<key dir> -o<setting enabler file>

Check the environment of execution and create required files.

-k: Specify the directory in which keys are (default: ${THIS_DIR}/key)
-o: Specify the file to enable setting (default: ${THIS_DIR}/enable_ansible_setting.sh)
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opt_k="${THIS_DIR}/key"
opt_o="${THIS_DIR}/enable_ansible_setting.sh"

for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -k*)                 opt_k="${arg#-k}"    ;;
    -o*)                 opt_o="${arg#-o}"    ;;
    *)
      echo "ERROR:${0##*/}: invalid args" 1>&2
      exit 1
      ;;
  esac
done

KEY_DIR="${opt_k}"
ENABLER_FILE="${opt_o}"

#####################################################################
# setting
#####################################################################

TOP_DIR=$(dirname "${THIS_DIR}")

SETTING_FILE="${TOP_DIR}/common_setting.json"

FILES_DIR="${THIS_DIR}/roles/setup_virt_env/files"

CONFIG_FILE="${THIS_DIR}/ansiblg.cfg"

SEC_KEY_FILE="${KEY_DIR}/id_rsa"
PUB_KEY_FILE="${KEY_DIR}/id_rsa.pub"

LIMIT_TIME='5'

HOST_VER_DIR="${THIS_DIR}/host_vars"
BARE_SETTING_FILE="${HOST_VER_DIR}/bare_host.yml"
VIRT_SETTING_FILE="${HOST_VER_DIR}/virt_host.yml"

#####################################################################
# check local tool
#####################################################################

if ! type jq >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: jq command not found" 1>&2
  exit 1
fi

#####################################################################
# check setting file
#####################################################################

if [ ! -f "${SETTING_FILE}" ]; then
  echo "ERROR:${0##*/}: setting file not found <${SETTING_FILE}>" 1>&2
  exit 1
fi

if ! jq . "${SETTING_FILE}" >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: invalid file for JSON <${SETTING_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# check required tool
#####################################################################

if ! type ansible >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: ansible command not found" 1>&2
  exit 1
fi

if ! type pip3 >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: pip3 command not found" 1>&2
  exit 1
fi

if ! pip3 freeze | grep -q '^passlib'; then
  echo "ERROR:${0##*/}: passlib package not found" 1>&2
  exit 1
fi

if ! pip3 freeze | grep -q '^jmespath'; then
  echo "ERROR:${0##*/}: jmespath package not found" 1>&2
  exit 1
fi

#####################################################################
# import important parameter
#####################################################################

DB_HOST="$(jq -r '.COMMON_DB_HOST' "${SETTING_FILE}")"
DB_PORT="$(jq -r '.COMMON_DB_PORT' "${SETTING_FILE}")"
BARE_SSH_PORT="$(jq -r '.COMMON_BARE_SSH_PORT' "${SETTING_FILE}")"
VIRT_SSH_PORT="$(jq -r '.COMMON_VIRT_SSH_PORT' "${SETTING_FILE}")"

#####################################################################
# check parameter
#####################################################################

if ! printf '%s\n' "${DB_HOST}" | grep -Eq '^[0-9]+(\.[0-9]+){3}$'; then
  echo "ERROR:${0##*/}: invalid IP adress <${DB_HOST}>" 1>&2
  exit 1
fi

if ! printf '%s\n' "${DB_PORT}" | grep -Eq '^[0-9]+$'; then
  echo "ERROR:${0##*/}: invalid port number <${DB_PORT}>" 1>&2
  exit 1
fi

if ! printf '%s\n' "${BARE_SSH_PORT}" | grep -Eq '^[0-9]+$'; then
  echo "ERROR:${0##*/}: invalid port number <${BARE_SSH_PORT}>" 1>&2
  exit 1
fi

if ! printf '%s\n' "${VIRT_SSH_PORT}" | grep -Eq '^[0-9]+$'; then
  echo "ERROR:${0##*/}: invalid port number <${VIRT_SSH_PORT}>" 1>&2
  exit 1
fi

#####################################################################
# check user's key
##################################################################### 

if [ ! -f "${SEC_KEY_FILE}" ]; then
  echo "ERROR:${0##/}: secret key not found <${SEC_KEY_FILE}>"
  exit 1
fi

if [ ! -f "${PUB_KEY_FILE}" ]; then
  echo "ERROR:${0##/}: secret key not found <${SEC_KEY_FILE}>"
  exit 1
fi

chmod 600 "${SEC_KEY_FILE}"

if ! timeout "${LIMIT_TIME}" ssh -n -i "${SEC_KEY_FILE}" "postgres@${DB_HOST}" 'true'; then
  echo "ERROR:${0##*/}: cannot access to ${DB_HOST}:${BARE_SSH_PORT}" 1>&2
  exit 1
fi

#####################################################################
# check remote tool
#####################################################################

if ! timeout "${LIMIT_TIME}" ssh -n -i "${SEC_KEY_FILE}" "postgres@${DB_HOST}" \
  'type docker' >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: docker command not found on <${DB_HOST}>" 1>&2
  exit 1
fi

#####################################################################
# locate file
#####################################################################

mkdir -p "${FILES_DIR}"

cp "${PUB_KEY_FILE}" "${FILES_DIR%/}/"

mkdir -p "${HOST_VER_DIR}"

cat <<EOF | cat >"${BARE_SETTING_FILE}"
---
ansible_host: "${DB_HOST}"
ansible_port: "${BARE_SSH_PORT}"
EOF

cat <<EOF | cat >"${VIRT_SETTING_FILE}"
---
ansible_host: "${DB_HOST}"
ansible_port: "${VIRT_SSH_PORT}"
EOF

#####################################################################
# export parameter 
#####################################################################

cat <<EOF >"${ENABLER_FILE}"
export ANSIBLE_CONFIG="${CONFIG_FILE}"
export ANSIBLE_PRIVATE_KEY_FILE="${SEC_KEY_FILE}"
EOF
