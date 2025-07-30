#!/bin/bash
set -eu

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name>
Options : -c -j -s<serial number>  

Get all of evaluation data on the table.

-c: Enable output in form of CSV.
-j: Enable output in form of JSON.
-s: Specify the serial number of the table (default: the latest).
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr_p=''
opr_v=''
opr_n=''
opt_j='no'
opt_c='no'
opt_s='-1'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -j)                  opt_j='yes'          ;;
    -c)                  opt_c='yes'          ;;
    -s*)                 opt_s="${arg#-s}"    ;;
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

if [ "${opt_j}" = 'yes' ] && [ "${opt_c}" = 'yes' ]; then
  echo "ERROR:${0##*/}: invalid option specification" 1>&2
  exit 1
fi

if ! printf '%s\n' "${opt_s}" | grep -Eq '^-?[0-9]+$'; then
  echo "ERROR:${0##*/}: invalid number specified <${opt_s}>" 1>&2
  exit 1
fi

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"

IS_JSON="${opt_j}"
IS_CSV="${opt_c}"
SERIAL_NUM="${opt_s}"

#####################################################################
# common setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
SETTING_FILE="${THIS_DIR}/../source_common_setting.sh"

if [ ! -f "${SETTING_FILE}" ]; then
  echo "ERROR:${0##*/}: setting file not found <${SETTING_FILE}>" 1>&2
  exit 1
fi

. "${SETTING_FILE}"

#####################################################################
# setting
#####################################################################

DB_NAME="${COMMON_DB_NAME}"
DB_HOST="${COMMON_DB_HOST}"
DB_PORT="${COMMON_DB_PORT}"

REFER_ROLE_NAME="${COMMON_REFER_ROLE_NAME}"

DEVICE_SCHEMA_NAME="device_${DEVICE_NAME}_schema"

EVALDATA_TABLE_NAME_PREFIX="eval_${PROJECT_NAME}_${PROJECT_VERSION}_${DEVICE_NAME}"

#####################################################################
# check 
#####################################################################

if ! type psql >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: psql command not found" 1>&2
  exit 1
fi

db_refer_command() {
  local COMMAND="$1"

  psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c "${COMMAND}" \
    -t --csv
}

#####################################################################
# get last table name
#####################################################################

if [ "${SERIAL_NUM}" -ge 0 ]; then
  format_serial_num=$(printf '%02d\n' "${SERIAL_NUM}")
  target_table_name="${EVALDATA_TABLE_NAME_PREFIX%_}_${format_serial_num}"
else
  target_table_name=$(
    db_refer_command '\dt '"${DEVICE_SCHEMA_NAME}.*"                |
    awk -F, '{ print $2; }'                                         |
    grep "^${EVALDATA_TABLE_NAME_PREFIX}"                           |
    sort                                                            |
    tail -n 1
  )
fi

abs_target_table_name="${DEVICE_SCHEMA_NAME}.${target_table_name}"

#####################################################################
# get data
#####################################################################

if [ "${IS_JSON}" = 'yes' ]; then
  psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -t \
    -c \
    "SELECT to_json(${abs_target_table_name})
     FROM ${abs_target_table_name} WHERE validity = 'TRUE'"
elif [ "${IS_CSV}" = 'yes' ]; then
  psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -t --csv \
    -c "SELECT * FROM ${abs_target_table_name} WHERE validity = 'TRUE'"
else
  psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c "SELECT * FROM ${abs_target_table_name} WHERE validity = 'TRUE'"
fi
