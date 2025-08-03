#!/bin/bash
set -eu

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <device name> <file>
Options : 

Create input description table and output description table.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr_n=''
opr_f=''

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    *)
      if   [ $((i+1)) -eq $# ] && [ -z "${opr_n}" ]; then
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

DEVICE_NAME="${opr_n}"
JSON_FILE="${opr_f}"

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

REFER_ROLE_NAME="${COMMON_REFER_ROLE_NAME}"

INPUT_DESC_TABLE_NAME="${COMMON_INPUT_DESC_TABLE_NAME}"
OUTPUT_DESC_TABLE_NAME="${COMMON_OUTPUT_DESC_TABLE_NAME}"

SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

ABS_INPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${INPUT_DESC_TABLE_NAME}"
ABS_OUTPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${OUTPUT_DESC_TABLE_NAME}"

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
FILE_DIR="${THIS_DIR}/../file"
INPUT_DESC_ITEM_JSON_FILE="${FILE_DIR}/input_description_item.json"
OUTPUT_DESC_ITEM_JSON_FILE="${FILE_DIR}/output_description_item.json"

#####################################################################
# check json
#####################################################################

if ! jq . "${JSON_FILE}" >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: invalid json file specified <${JSON_FILE}>" 1>&2
  exit 1
fi

if [ -z "$(jq '.in // empty' "${JSON_FILE}")" ]; then
  echo "ERROR:${0##*/}: in item not found <${JSON_FILE}>" 1>&2
  exit 1
fi

if [ -z "$(jq '.out // empty' "${JSON_FILE}")" ]; then
  echo "ERROR:${0##*/}: out item not found <${JSON_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# Create input description table
#####################################################################

if db_refer_command '\dt '"${SCHEMA_NAME}"'.*' 2>/dev/null |
   awk -F',' '{ print $2; }' | grep -q "^${INPUT_DESC_TABLE_NAME}$"; then
  echo "INFO:${0##*/}: table already exists <${ABS_INPUT_DESC_TABLE_NAME}>" 1>&2
else
  create_input_description_table_command=$(
     jq -c '.[]' "${INPUT_DESC_ITEM_JSON_FILE}" |
     while read -r line
     do
       input_name=$(printf '%s\n' "${line}" | jq -r '.name // empty')
       input_type=$(printf '%s\n' "${line}" | jq -r '.type // empty')

       printf '%s %s,\n' "${input_name}" "${input_type}"
     done |
     sed '$s!,$!!' |
     {
       echo "CREATE TABLE ${ABS_INPUT_DESC_TABLE_NAME} ("
       cat
       echo ');'
     }
  )

  db_manage_table_command "${create_input_description_table_command}"

  db_manage_table_command \
    "GRANT SELECT ON TABLE ${ABS_INPUT_DESC_TABLE_NAME} TO ${REFER_ROLE_NAME};"
fi

#####################################################################
# Create output table
#####################################################################

if db_refer_command '\dt '"${SCHEMA_NAME}"'.*' 2>/dev/null |
   awk -F',' '{ print $2; }' | grep -q "^${OUTPUT_DESC_TABLE_NAME}$"; then
  echo "INFO:${0##*/}: table already exists <${ABS_OUTPUT_DESC_TABLE_NAME}>" 1>&2
else
  create_output_description_table_command=$(
     jq -c '.[]' "${OUTPUT_DESC_ITEM_JSON_FILE}" |
     while read -r line
     do
       output_name=$(printf '%s\n' "${line}" | jq -r '.name // empty')
       output_type=$(printf '%s\n' "${line}" | jq -r '.type // empty')

       printf '%s %s,\n' "${output_name}" "${output_type}"
     done |
     sed '$s!,$!!' |
     {
       echo "CREATE TABLE ${ABS_OUTPUT_DESC_TABLE_NAME} ("
       cat
       echo ');'
     }
  )

  db_manage_table_command "${create_output_description_table_command}"

  db_manage_table_command \
    "GRANT SELECT ON TABLE ${ABS_OUTPUT_DESC_TABLE_NAME} TO ${REFER_ROLE_NAME};"
fi

#####################################################################
# Insert input table
#####################################################################

old_input_names=$(
  db_refer_command \
    "SELECT input_name FROM ${ABS_INPUT_DESC_TABLE_NAME}
     ORDER BY input_name;"
)

new_input_names=$(jq -r '.in.[].name' "${JSON_FILE}" | sort)

only_old_input_names=$(
  join -1 1 -2 1 -v 1 \
    <(printf '%s\n' "${old_input_names}") \
    <(printf '%s\n' "${new_input_names}")
)

if [ -n "${only_old_input_names}" ]; then
  only_old_input_names_csv=$(printf '%s' "${only_old_input_names}" | tr '\n' ',')

  printf 'ERROR:%s: there are input items that exist only on database <%s>\n' \
    "${0##*/}" "${only_old_input_names_csv}"
  exit 1
fi

db_manage_table_command \
  "DELETE FROM ${ABS_INPUT_DESC_TABLE_NAME};" >/dev/null
db_manage_table_command \
  "SELECT SETVAL ('${ABS_INPUT_DESC_TABLE_NAME}_input_id_seq', 1, false);" >/dev/null

jq '.in[]' -c "${JSON_FILE}" |
while read -r line
do
  input_name=$(printf '%s\n' "${line}" | jq -r ".name // empty")
  input_type=$(printf '%s\n' "${line}" | jq -r ".type // empty")
  input_unit=$(printf '%s\n' "${line}" | jq -r ".unit // empty")
  input_description=$(printf '%s\n' "${line}" | jq -r ".description // empty")

  input_cmd=''
  input_cmd="${input_cmd} INSERT into ${ABS_INPUT_DESC_TABLE_NAME}"
  input_cmd="${input_cmd} (input_name,input_type,input_unit,input_description)"
  input_cmd="${input_cmd} VALUES"
  input_cmd="${input_cmd} ('${input_name}','${input_type}','${input_unit}','${input_description}')"

  db_manage_table_command "${input_cmd}" >/dev/null
done

#####################################################################
# Insert output table
#####################################################################

old_output_names=$(
  db_refer_command \
    "SELECT output_name FROM ${ABS_OUTPUT_DESC_TABLE_NAME}
     ORDER BY output_name;"
)

new_output_names=$(jq -r ".out.[].name" "${JSON_FILE}" | sort)

only_old_output_names=$(
  join -1 1 -2 1 -v 1 \
    <(printf '%s\n' "${old_output_names}") \
    <(printf '%s\n' "${new_output_names}")
)

if [ -n "${only_old_output_names}" ]; then
  only_old_output_names_csv=$(printf '%s' "${only_old_output_names}" | tr '\n' ',')

  printf 'ERROR:%s: there are output items that exist only on database <%s>\n' \
    "${0##*/}" "${only_old_output_names_csv}"
  exit 1
fi

db_manage_table_command \
  "DELETE FROM ${ABS_OUTPUT_DESC_TABLE_NAME};" >/dev/null
db_manage_table_command \
  "SELECT SETVAL ('${ABS_OUTPUT_DESC_TABLE_NAME}_output_id_seq', 1, false);" >/dev/null

jq '.out[]' -c "${JSON_FILE}" |
while read -r line
do
  output_name=$(printf '%s\n' "${line}" | jq -r ".name // empty")
  output_type=$(printf '%s\n' "${line}" | jq -r ".type // empty")
  output_unit=$(printf '%s\n' "${line}" | jq -r ".unit // empty")
  output_description=$(printf '%s\n' "${line}" | jq -r ".description // empty")

  output_cmd=''
  output_cmd="${output_cmd} INSERT into ${ABS_OUTPUT_DESC_TABLE_NAME}"
  output_cmd="${output_cmd} (output_name,output_type,output_unit,output_description)"
  output_cmd="${output_cmd} VALUES"
  output_cmd="${output_cmd} ('${output_name}','${output_type}','${output_unit}','${output_description}')"

  db_manage_table_command "${output_cmd}" >/dev/null
done
