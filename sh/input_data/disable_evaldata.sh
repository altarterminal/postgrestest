#!/bin/bash
set -eu

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name> <ID> <reason>
Options : -s<serial>

Disable evaluation data.

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
opr_i=''
opr_r=''
opt_s='-1'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -s*)                 opt_s="${arg#-s}"    ;;
    *)
      if   [ $((i+4)) -eq $# ] && [ -z "${opr_p}" ]; then
        opr_p="${arg}"
      elif [ $((i+3)) -eq $# ] && [ -z "${opr_v}" ]; then
        opr_v="${arg}"
      elif [ $((i+2)) -eq $# ] && [ -z "${opr_n}" ]; then
        opr_n="${arg}"
      elif [ $((i+1)) -eq $# ] && [ -z "${opr_i}" ]; then
        opr_i="${arg}"
      elif [ $((i+0)) -eq $# ] && [ -z "${opr_r}" ]; then
        opr_r="${arg}"
       else
        echo "ERROR:${0##*/}: invalid args" 1>&2
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

if ! printf '%s\n' "${opt_s}" | grep -Eq '^-?[0-9]+$'; then
  echo "ERROR:${0##*/}: invalid number specified <${opt_s}>" 1>&2
  exit 1
fi

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"
TARGET_IDS="${opr_i}"
DISABLE_REASON="${opr_r}"

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

MANAGE_TABLE_ROLE_NAME="${COMMON_MANAGE_TABLE_ROLE_NAME}"
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

if ! type jq >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: jq command not found" 1>&2
  exit 1
fi

#####################################################################
# utility
#####################################################################

db_manage_table_command() {
  local COMMAND="$1"

  psql "${DB_NAME}" \
    -U "${MANAGE_TABLE_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c "${COMMAND}"
}

db_refer_command() {
  local COMMAND="$1"

  psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c "${COMMAND}" \
    -t --csv
}

db_refer_command_raw() {
  local COMMAND="$1"

  psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c "${COMMAND}"
}

#####################################################################
# check reason
#####################################################################

if [ -z "${DISABLE_REASON}" ]; then
  echo "ERROR:${0##*/}: disable reason must be specified" 1>&2
  exit 1
fi

#####################################################################
# decompose ids
#####################################################################

decomposed_ids=$(
  printf '%s\n' "${TARGET_IDS}" | tr ',' '\n' |
  awk -F'-' '
  NF == 1 { print; }
  NF >  1 {
    if ($1 < $2) { min = $1; max = $2; }
    else         { min = $2; max = $1; }
    for (i=min; i<=max; i++) { print i; }
  }
  ' |
  sort -n | uniq
)

#####################################################################
# determine table name
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
# get target data
#####################################################################

comma_quote_ids=$(
  printf '%s\n' "${decomposed_ids}" |
  sed 's!^!'"'"'!' | sed 's!$!'"'"'!' |
  tr '\n' ',' | sed 's!,$!!'
)

target_content=$(
  db_refer_command_raw \
    "SELECT * FROM ${abs_target_table_name} 
     WHERE measure_id IN (${comma_quote_ids});"
)

#####################################################################
# ask for user's confirmation
#####################################################################

echo '~~~ Target rows are From here'
printf '%s\n' "${target_content}"
echo '~~~ Target rows are To here'
echo ''
printf '%s' 'Target rows are above. Do you want to disable them? [Y/n] '

read -r user_input

if [ "${user_input}" != 'Y' ]; then
  echo "Your input is <${user_input}>. Nothing is done."
  exit
fi

#####################################################################
# disable target
#####################################################################

db_manage_table_command "
  UPDATE ${abs_target_table_name} 
  SET (validity, free_description) = ('FALSE', '${DISABLE_REASON}')
  A
  WHERE measure_id IN (${comma_quote_ids});"
