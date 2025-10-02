#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit() {
  cat <<USAGE 1>&2
Usage   : ${0##*/} <param file>
Options : -i -k<key dir> -o<setting enabler file>

Check the environment of execution and create required files.

-i: Enable the setting of initialization state (default: only for stable state).
-k: Specify the directory in which keys are (default: ./key)
-o: Specify the file to enable setting (default: ./enable_setting.sh)
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr=''
opt_i='no'
opt_k='./key'
opt_o='./enable_setting.sh' 

i=1
for arg in ${1+"$@"}; do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -i)                  opt_i='yes'          ;;
    -k*)                 opt_k="${arg#-k}"    ;;
    -o*)                 opt_o="${arg#-o}"    ;;
    *)
      if [ $i -eq $# ] && [ -z "${opr}" ]; then
        opr="${arg}"
      else
        echo "ERROR:${0##*/}: invalid args" 1>&2
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

PARAM_FILE="${opr}"
IS_INIT_TOO="${opt_i}"
KEY_DIR="${opt_k}"
ENABLER_FILE="${opt_o}"

#####################################################################
# setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "$0")")
SH_DIR=$(dirname "${THIS_DIR}")

TOP_DIR=$(dirname "${SH_DIR}")
ANSIBLE_DIR="${TOP_DIR}/ansible"
TEMPLATE_DIR="${TOP_DIR}/template"

TEMPLATE_SETTING_FILE="${TEMPLATE_DIR}/template_setting.json"
COMMON_SETTING_FILE="${TOP_DIR}/common_setting.json"

SH_CREATE_FILE="${SH_DIR}/create_sh_setting_enabler.sh"
SH_ENABLER_FILE="${SH_DIR}/enable_sh_setting.sh"

ANSIBLE_CREATE_FILE="${ANSIBLE_DIR}/create_ansible_setting_enabler.sh"
ANSIBLE_ENABLER_FILE="${ANSIBLE_DIR}/enable_ansible_setting.sh"

#####################################################################
# check
#####################################################################

if [ ! -f "${ANSIBLE_CREATE_FILE}" ] || [ ! -x "${ANSIBLE_CREATE_FILE}" ]; then
  echo "ERROR:${0##*/}: invalid file specified <${ANSIBLE_CREATE_FILE}>" 1>&2
  exit 1
fi

if [ ! -f "${SH_CREATE_FILE}" ] || [ ! -x "${SH_CREATE_FILE}" ]; then
  echo "ERROR:${0##*/}: invalid file specified <${SH_CREATE_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# import and check param
#####################################################################

if [ ! -f "${PARAM_FILE}" ] || [ ! -r "${PARAM_FILE}" ]; then
  echo "ERROR:${0##*/}: invalid file specified <${PARAM_FILE}>" 1>&2
  exit 1
fi

if ! jq . "${PARAM_FILE}" >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: file not JSON <${PARAM_FILE}>" 1>&2
  exit 1
fi

DATABASE_HOST=$(jq -r '.DATABASE_HOST // empty'  "${PARAM_FILE}")
DATABASE_PORT=$(jq -r '.DATABASE_PORT // empty'  "${PARAM_FILE}")
DATABASE_NET=$(jq -r '.DATABASE_NET // empty'  "${PARAM_FILE}")

if [ -z "${DATABASE_HOST}" ]; then
  echo "ERROR:${0##*/}: DATABASE_HOST not found <${PARAM_FILE}>" 1>&2
  exit 1
fi

if [ -z "${DATABASE_PORT}" ]; then
  echo "ERROR:${0##*/}: DATABASE_PORT not found <${PARAM_FILE}>" 1>&2
  exit 1
fi

if [ -z "${DATABASE_NET}" ]; then
  echo "ERROR:${0##*/}: DATABASE_NET not found <${PARAM_FILE}>" 1>&2
  exit 1
fi

jq . "${TEMPLATE_SETTING_FILE}" |
  jq '."COMMON_DB_HOST" = "'"${DATABASE_HOST}"'"' |
  jq '."COMMON_DB_PORT" = "'"${DATABASE_PORT}"'"' |
  jq '."COMMON_DB_NET" = "'"${DATABASE_NET}"'"' |
  cat >"${COMMON_SETTING_FILE}"

#####################################################################
# ansible
#####################################################################

if [ "${IS_INIT_TOO}" = 'no' ]; then
  : >"${ENABLER_FILE}"
else
  if ! "${ANSIBLE_CREATE_FILE}" -k"${KEY_DIR}" -o"${ANSIBLE_ENABLER_FILE}"; then
    echo "ERROR:${0##*/}: ansible setting failed" 1>&2
    exit 1
  fi

  printf '%s\n' ". ${ANSIBLE_ENABLER_FILE}" >"${ENABLER_FILE}"
fi

#####################################################################
# shell script
#####################################################################

if ! "${SH_CREATE_FILE}" -o"${SH_ENABLER_FILE}"; then
  echo "ERROR:${0##*/}: sh setting failed" 1>&2
  exit 1
fi

printf '%s\n' ". ${SH_ENABLER_FILE}" >>"${ENABLER_FILE}"
