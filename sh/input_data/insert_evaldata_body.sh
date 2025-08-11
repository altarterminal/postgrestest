#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name> <file>
Options : 

Insert an evaluation data into the table.

-d: Enable dry-run (only judge whether you can insert the data).
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr_p=''
opr_v=''
opr_n=''
opr_f=''
opt_d='no'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -d)                  opt_d='yes'          ;;
    *)
      if   [ $((i+3)) -eq $# ] && [ -z "${opr_p}" ]; then
        opr_p="${arg}"
      elif [ $((i+2)) -eq $# ] && [ -z "${opr_v}" ]; then
        opr_v="${arg}"
      elif [ $((i+1)) -eq $# ] && [ -z "${opr_n}" ]; then
        opr_n="${arg}"
      elif [ $((i+0)) -eq $# ] && [ -z "${opr_f}" ]; then
        opr_f="${arg}"
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

if [ ! -f "${opr_f}" ] || [ ! -r "${opr_f}" ]; then
  echo "ERROR:${0##*/}: invalid file specified <${opr_f}>" 1>&2
  exit 1
fi

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"
JSON_FILE="${opr_f}"

IS_DRYRUN="${opt_d}"

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

COMMON_SCHEMA_NAME="${COMMON_COMMON_SCHEMA_NAME}"
DEVICE_SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

ABS_IMAGE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${COMMON_IMAGE_TABLE_NAME}"
ABS_REALDEVICE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${COMMON_REALDEVICE_TABLE_NAME}"

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
TOOL_DIR="${THIS_DIR}/../tool"
GET_LAST_TABLE_NAME="${TOOL_DIR}/get_last_table_name.sh"
GET_ITEM_NAMES="${TOOL_DIR}/get_item_names.sh"

#####################################################################
# check json
#####################################################################

if ! jq . "${JSON_FILE}" >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: invalid json file specified <${JSON_FILE}>" 1>&2
  exit 1
fi

if [ -z "$(jq ".in // empty" "${JSON_FILE}")" ]; then
  echo "ERROR:${0##*/}: in item not found <${JSON_FILE}>" 1>&2
  exit 1
fi

if [ -z "$(jq ".out // empty" "${JSON_FILE}")" ]; then
  echo "ERROR:${0##*/}: out item not found <${JSON_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# check the measurer mail
#####################################################################

evaldata_measurer_mail=$(jq -r '."measurer_mail"' "${JSON_FILE}")

if ! printf '%s\n' "${evaldata_measurer_mail}" | grep -Eq '^[^@]+@sample\.co\.jp$'; then
  echo "ERROR:${0##*/}: invalid mail specified <${JSON_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# check the image
#####################################################################

evaldata_image_md5sum=$(jq -r '."image_md5sum"' "${JSON_FILE}")

image_id=$(
  db_refer_command \
    "SELECT image_id FROM ${ABS_IMAGE_TABLE_NAME}
     WHERE image_md5sum = '${evaldata_image_md5sum}'"
)

if [ -z "${image_id}" ]; then
  echo "ERROR:${0##*/}: image not registered on image table <${evaldata_image_md5sum}>" 1>&2
  exit 1
fi

#####################################################################
# check the realdevice
#####################################################################

evaldata_realdevice_serial=$(jq -r '."realdevice_serial"' "${JSON_FILE}")

realdevice_id=$(
  db_refer_command \
    "SELECT realdevice_id FROM ${ABS_REALDEVICE_TABLE_NAME}
     WHERE realdevice_serial = '${evaldata_realdevice_serial}'"
)

if [ -z "${realdevice_id}" ]; then
  echo "ERROR:${0##*/}: realdevice not registered on realdevice table <${evaldata_realdevice_serial}>" 1>&2
  exit 1
fi

#####################################################################
# get last table name
#####################################################################

target_table_name=$(
  ${GET_LAST_TABLE_NAME} \
    "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}"
)
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get table name failed" 1>&2
  exit "${exit_code}"
fi

abs_target_table_name="${DEVICE_SCHEMA_NAME}.${target_table_name}"

#####################################################################
# check the consistency
#####################################################################

target_input_names=$(
  ${GET_ITEM_NAMES} -i \
    "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}"
)
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get input item names failed" 1>&2
  exit "${exit_code}"
fi

target_output_names=$(
  ${GET_ITEM_NAMES} -o \
    "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}"
)
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get output item names failed" 1>&2
  exit "${exit_code}"
fi

evaldata_input_names=$(jq -r '.in | keys | .[]' "${JSON_FILE}" | sort)

evaldata_output_names=$(jq -r '.out | keys | .[]' "${JSON_FILE}" | sort)

if ! diff \
    <(printf '%s\n' "${evaldata_input_names}") \
    <(printf '%s\n' "${target_input_names}")
then
  echo "ERROR:${0##*/}: there is inconsistent on input items between file and table"
  exit 1
fi

if ! diff \
  <(printf '%s\n' "${evaldata_output_names}") \
  <(printf '%s\n' "${target_output_names}")
then
  echo "ERROR:${0##*/}: there is inconsistent on output items between file and table"
  exit 1
fi

#####################################################################
# create insert command
#####################################################################

this_date=$(date '+%Y-%m-%d %H:%M:%S')
default_validity='TRUE'

insert_key_value_pairs=$(
{
  # common item #####################################################
  jq 'to_entries' "${JSON_FILE}"                                    |
  jq '.[] | select(.key != "in") | select(.key != "out")'           |
  jq 'select(.key != "image_md5sum")'                               |
  jq 'select(.key != "realdevice_serial")'                          |
  { 
    cat
    printf '{"key":"%s","value":"%s"}\n' 'measure_date'  "${this_date}"
    printf '{"key":"%s","value":"%s"}\n' 'validity'      "${default_validity}"
    printf '{"key":"%s","value":"%s"}\n' 'image_id'      "${image_id}"
    printf '{"key":"%s","value":"%s"}\n' 'realdevice_id' "${realdevice_id}"
  }                                                                 |
  jq -c

  # input item ######################################################
  jq '.in' "${JSON_FILE}"                                           |
  jq 'to_entries'                                                   |
  jq -c '.[]'

  # output item #####################################################
  jq '.out' "${JSON_FILE}"                                          |
  jq 'to_entries'                                                   |
  jq -c '.[]'
}                                                                   |

jq -s | jq 'sort_by(.key)' | jq -c '.[]'
)

key_tuple=$(
  printf '%s\n' "${insert_key_value_pairs}" |
  while read -r line
  do
    key=$(printf '%s\n' "${line}" | jq -r '.key')
    printf "%s," "${key}"
  done |
  sed 's!,$!!'
)

val_tuple=$(
  printf '%s\n' "${insert_key_value_pairs}" |
  while read -r line
  do
    val=$(printf '%s\n' "${line}" | jq -r '.value')
    printf "'%s'," "${val}"
  done |
  sed 's!,$!!'
)

insert_command=''
insert_command="${insert_command} INSERT into ${abs_target_table_name}"
insert_command="${insert_command} (${key_tuple})"
insert_command="${insert_command} VALUES"
insert_command="${insert_command} (${val_tuple})"

#####################################################################
# register (or dry-run)
#####################################################################

if [ "${IS_DRYRUN}" = 'yes' ]; then
  printf 'You can insert the data into <%s>.\n' "${abs_target_table_name}"
  echo '~~~ Insert Command from here'
  printf '%s\n' "${insert_command}"
  echo '~~~ Insert Command to here'
else
  db_manage_table_command "${insert_command}"
fi
