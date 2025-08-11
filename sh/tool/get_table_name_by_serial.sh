#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name> <serial num>
Options :

Get table name by serial number.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr_p=''
opr_v=''
opr_n=''
opr_s=''

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    *)
      if   [ $((i+3)) -eq $# ] && [ -z "${opr_p}" ]; then
        opr_p="${arg}"
      elif [ $((i+2)) -eq $# ] && [ -z "${opr_v}" ]; then
        opr_v="${arg}"
      elif [ $((i+1)) -eq $# ] && [ -z "${opr_n}" ]; then
        opr_n="${arg}"
      elif [ $((i+0)) -eq $# ] && [ -z "${opr_s}" ]; then
        opr_s="${arg}"
      else
        echo "ERROR:${0##*/}: invalid args" 1>&2
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

if ! printf '%s\n' "${opr_s}" | grep -Eq '^[0-9]+$'; then
  echo "ERROR:${0##*/}: invalid number specified <${opr_s}>" 1>&2
  exit 1
fi

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"
SERIAL_NUM="${opr_s}"

#####################################################################
# common setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
SETTING_FILE="${THIS_DIR}/../enable_sh_setting.sh"

if [ ! -f "${SETTING_FILE}" ]; then
  echo "ERROR:${0##*/}: setting file not found <${SETTING_FILE}>" 1>&2
  exit 1
fi

. "${SETTING_FILE}"

#####################################################################
# setting
#####################################################################

DEVICE_SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

EVALDATA_TABLE_NAME=$(
  printf '%s_%s_%s_%s_%02d\n' \
    "${COMMON_EVALDATA_TABLE_PREFIX}" \
    "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}" \
    "${SERIAL_NUM##0}"
)

#####################################################################
# check whether table exists
#####################################################################

table_list=$(db_refer_command '\dt '"${DEVICE_SCHEMA_NAME}.*")
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get table list failed" 1>&2
  exit 1
fi

target_table_name=$(
  printf '%s\n' "${table_list}" | awk -F, '{ print $2; }' |
  grep "^${EVALDATA_TABLE_NAME}$"
)

if [ -z "${target_table_name}" ]; then
  echo "ERROR:${0##*/}: table not found" 1>&2
  exit 1
fi

printf '%s\n' "${target_table_name}"
