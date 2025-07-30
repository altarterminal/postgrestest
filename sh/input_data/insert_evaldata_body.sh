#!/bin/bash
set -eu

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

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"
JSON_FILE="${opr_f}"
IS_DRYRUN="${opt_d}"

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

COMMON_SCHEMA_NAME="${COMMON_COMMON_SCHEMA_NAME}"
DEVICE_SCHEMA_NAME="device_${DEVICE_NAME}_schema"

EVALDATA_TABLE_NAME_PREFIX="eval_${PROJECT_NAME}_${PROJECT_VERSION}_${DEVICE_NAME}"

ABS_IMAGE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${COMMON_IMAGE_TABLE_NAME}"
ABS_REALDEVICE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${COMMON_REALDEVICE_TABLE_NAME}"

ABS_INPUT_DESC_TABLE_NAME="${DEVICE_SCHEMA_NAME}.${COMMON_INPUT_DESC_TABLE_NAME}"
ABS_OUTPUT_DESC_TABLE_NAME="${DEVICE_SCHEMA_NAME}.${COMMON_OUTPUT_DESC_TABLE_NAME}"

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
    -U "${MANAGE_TABLE_ROLE_NAME}" \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -c "${COMMAND}"
}

db_refer_command() {
  local COMMAND="$1"

  psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -c "${COMMAND}" \
    -A -t -F,
}

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
  db_refer_command "SELECT image_id FROM ${ABS_IMAGE_TABLE_NAME} 
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
  db_refer_command "SELECT realdevice_id FROM ${ABS_REALDEVICE_TABLE_NAME}
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
  db_refer_command '\dt '"${DEVICE_SCHEMA_NAME}.*"                  |
  awk -F, '{ print $2; }'                                           |
  grep "^${EVALDATA_TABLE_NAME_PREFIX}"                             |
  sort                                                              |
  tail -n 1
)

abs_target_table_name="${DEVICE_SCHEMA_NAME}.${target_table_name}"

#####################################################################
# check the consistency
#####################################################################

candidate_input_names=$(
  db_refer_command "SELECT input_name FROM 
    ${ABS_INPUT_DESC_TABLE_NAME}" |
  grep -v '^$' | sort
)
candidate_output_names=$(
  db_refer_command "SELECT output_name FROM 
    ${ABS_OUTPUT_DESC_TABLE_NAME}" |
  grep -v '^$' | sort
)

table_column_names=$(
  db_refer_command "SELECT column_name 
    FROM information_schema.columns
    WHERE table_name = '${target_table_name}'" |
  grep -v '^$' | sort
)

target_input_names=$(
  join -1 1 -2 1 -o1.1 \
    <(printf '%s\n' "${candidate_input_names}") \
    <(printf '%s\n' "${table_column_names}") 
)

target_output_names=$(
  join -1 1 -2 1 -o1.1 \
    <(printf '%s\n' "${candidate_output_names}") \
    <(printf '%s\n' "${table_column_names}") 
)

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
  printf '%s\n' "${insert_command}"
else
  db_manage_table_command "${insert_command}"
fi
