#!/bin/bash
set -u

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

if [ -z "${opr_p}" ]; then
  echo "ERROR:${0##*/}: project name must be specified" 1>&2
  exit 1
fi

if [ -z "${opr_v}" ]; then
  echo "error:${0##*/}: project version must be specified" 1>&2
  exit 1
fi

if [ -z "${opr_n}" ]; then
  echo "error:${0##*/}: device name must be specified" 1>&2
  exit 1
fi

if ! printf '%s\n' "${opr_i}" | grep -Eq '^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$'; then
  echo "error:${0##*/}: invalid ID specified <${opr_i}>" 1>&2
  exit 1
fi

if [ -z "${opr_r}" ]; then
  echo "ERROR:${0##*/}: disable reason must be specified" 1>&2
  exit 1
fi

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

DEVICE_SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
TOOL_DIR="${THIS_DIR}/../tool"
GET_TABLE_NAME_BY_SERIAL="${TOOL_DIR}/get_table_name_by_serial.sh"
GET_LAST_TABLE_NAME="${TOOL_DIR}/get_last_table_name.sh"

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
  target_table_name=$(
    ${GET_TABLE_NAME_BY_SERIAL} \
      "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}" \
      "${SERIAL_NUM}"
  )
else
  target_table_name=$(
    ${GET_LAST_TABLE_NAME} \
      "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}"
  )
fi

exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get table name failed" 1>&2
  exit "${exit_code}"
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
  db_refer_command_default "
     SELECT * FROM ${abs_target_table_name}
     WHERE measure_id IN (${comma_quote_ids});
  "
)

#####################################################################
# ask for user's confirmation
#####################################################################

echo '~~~ Target Rows are from here'
printf '%s\n' "${target_content}"
echo '~~~ Target Rows are to here'
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
  WHERE measure_id IN (${comma_quote_ids});
"
