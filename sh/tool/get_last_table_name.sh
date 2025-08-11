#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name>
Options :

Get last table name.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr_p=''
opr_v=''
opr_n=''

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    *)
      if   [ $((i+2)) -eq $# ] && [ -z "${opr_p}" ]; then
        opr_p="${arg}"
      elif [ $((i+1)) -eq $# ] && [ -z "${opr_v}" ]; then
        opr_v="${arg}"
      elif [ $((i+0)) -eq $# ] && [ -z "${opr_n}" ]; then
        opr_n="${arg}"
      else
        echo "ERROR:${0##*/}: invalid args" 1>&2
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"

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

EVALDATA_TABLE_NAME_PREFIX="${COMMON_EVALDATA_TABLE_PREFIX}_${PROJECT_NAME}_${PROJECT_VERSION}_${DEVICE_NAME}"

#####################################################################
# get last table name
#####################################################################

table_list=$(db_refer_command '\dt '"${DEVICE_SCHEMA_NAME}.*")
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get table list failed" 1>&2
  exit 1
fi

target_table_name=$(
  printf '%s\n' "${table_list}"                                     |
  awk -F, '{ print $2; }'                                           |
  grep "^${EVALDATA_TABLE_NAME_PREFIX}"                             |
  sort                                                              |
  tail -n 1
)

if [ -z "${target_table_name}" ]; then
  echo "INFO:${0##*/}: no table has not been created" 1>&2
fi

printf '%s\n' "${target_table_name}"
