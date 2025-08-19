#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit() {
  cat <<USAGE 1>&2
Usage   : ${0##*/}
Options : -s -k<key dir> -o<setting enabler file>

Check the environment of execution and create required files.

-s: Enable only the setting of stable state (i.e. input and output of data).
-k: Specify the directory in which keys are (default: ./key)
-o: Specify the file to enable setting (default: ./enable_setting.sh)
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opt_s='no'
opt_k='./key'
opt_o='./enable_setting.sh' 

for arg in ${1+"$@"}; do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -s)                  opt_s="${arg#-s}"    ;;
    -k*)                 opt_k="${arg#-k}"    ;;
    -o*)                 opt_o="${arg#-o}"    ;;
    *)
      echo "ERROR:${0##*/}: invalid args" 1>&2
      exit 1
      ;;
  esac
done

IS_ONLY_STABLE="${opt_s}"
KEY_DIR="${opt_k}"
ENABLER_FILE="${opt_o}"

#####################################################################
# setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "$0")")

ANSIBLE_DIR="${THIS_DIR}/ansible"
ANSIBLE_CREATE_FILE="${ANSIBLE_DIR}/create_ansible_setting_enabler.sh"
ANSIBLE_ENABLER_FILE="${ANSIBLE_DIR}/enable_ansible_setting.sh"

SH_DIR="${THIS_DIR}/sh"
SH_CREATE_FILE="${SH_DIR}/create_sh_setting_enabler.sh"
SH_ENABLER_FILE="${SH_DIR}/enable_sh_setting.sh"

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
# ansible
#####################################################################

if [ "${IS_ONLY_STABLE}" = 'yes' ]; then
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
