#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit() {
  cat <<USAGE 1>&2
Usage   : ${0##*/}
Options : -o<setting enabler file>

Cleanup the environment.

-o: Specify the file to enable setting (default: ./enable_setting.sh)
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opt_o='./enable_setting.sh' 

i=1
for arg in ${1+"$@"}; do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -o*)                 opt_o="${arg#-o}"    ;;
    *)
      echo "ERROR:${0##*/}: invalid args" 1>&2
      exit 1
      ;;
  esac

  i=$((i + 1))
done

ENABLER_FILE="${opt_o}"

#####################################################################
# setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "$0")")
SH_DIR=$(dirname "${THIS_DIR}")
TOP_DIR=$(dirname "${SH_DIR}")
ANSIBLE_DIR="${TOP_DIR}/ansible"

SH_ENABLER_FILE="${SH_DIR}/enable_sh_setting.sh"
ANSIBLE_ENABLER_FILE="${ANSIBLE_DIR}/enable_ansible_setting.sh"

#####################################################################
# delete setting enabler file
#####################################################################

[ -f "${ENABLER_FILE}" ] && rm "${ENABLER_FILE}"
[ -f "${SH_ENABLER_FILE}" ] && rm "${SH_ENABLER_FILE}"
[ -f "${ANSIBLE_ENABLER_FILE}" ] && rm "${ANSIBLE_ENABLER_FILE}"
