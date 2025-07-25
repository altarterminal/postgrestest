#!/bin/bash
set -eu

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <device name> <file>
Options : 

Create input table and output table.
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
      if   [ $((i + 1)) -eq $# ] && [ -z "${opr_n}" ]; then
        opr_n="${arg}"
      elif [ $i         -eq $# ] && [ -z "${opr_f}" ]; then
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
# setting
#####################################################################

DB_HOST="192.168.11.13"
DB_PORT="55432"
DB_NAME="eval_database"

REFER_ROLE_NAME="refer_role"
MANAGE_TABLE_ROLE_NAME="manage_table_role"
MANAGE_SCHEMA_ROLE_NAME="manage_schema_role"

SCHEMA_NAME="virtio_${DEVICE_NAME}_schema"

INPUT_DESC_TABLE_NAME='input_description_table'
OUTPUT_DESC_TABLE_NAME='output_description_table'

ABS_INPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${INPUT_DESC_TABLE_NAME}"
ABS_OUTPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${OUTPUT_DESC_TABLE_NAME}"

#####################################################################
# utility
#####################################################################

db_manage_schema_command() {
  local COMMAND="$1"

  psql "${DB_NAME}" \
    -U "${MANAGE_SCHEMA_ROLE_NAME}" \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -c "${COMMAND}"
}

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

if [ -z "$(jq ".in //empty" "${JSON_FILE}")" ]; then
  echo "ERROR:${0##*/}: in item not found <${JSON_FILE}>" 1>&2
  exit 1
fi

if [ -z "$(jq ".out //empty" "${JSON_FILE}")" ]; then
  echo "ERROR:${0##*/}: out item not found <${JSON_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# Create schema
#####################################################################

if db_refer_command '\dn' | awk -F',' '{ print $1; }' |
   grep -q "^${SCHEMA_NAME}$"; then
  echo "INFO:${0##*/}: table already exists <${SCHEMA_NAME}>" 1>&2
else
  db_manage_schema_command 'CREATE SCHEMA '"${SCHEMA_NAME}"

  db_manage_schema_command \
    "GRANT USAGE ON SCHEMA \"${SCHEMA_NAME}\" TO ${MANAGE_TABLE_ROLE_NAME},${REFER_ROLE_NAME};"
  db_manage_schema_command \
    "GRANT CREATE ON SCHEMA \"${SCHEMA_NAME}\" TO ${MANAGE_TABLE_ROLE_NAME};"
fi

#####################################################################
# Create input table
#####################################################################

if db_refer_command '\dt '"${SCHEMA_NAME}"'.*' 2>/dev/null | awk -F',' '{ print $2; }' |
   grep -q "^${INPUT_DESC_TABLE_NAME}$"; then
  echo "INFO:${0##*/}: table already exists <${ABS_INPUT_DESC_TABLE_NAME}>" 1>&2
else
  db_manage_table_command 'CREATE TABLE '"${ABS_INPUT_DESC_TABLE_NAME}"' (
    input_id SERIAL,
    input_name TEXT,
    input_type TEXT,
    input_unit TEXT,
    input_description TEXT
  )'

  db_manage_table_command \
    "GRANT SELECT ON TABLE \"${SCHEMA_NAME}\".\"${INPUT_DESC_TABLE_NAME}\" TO ${REFER_ROLE_NAME};"
fi

#####################################################################
# Create output table
#####################################################################

if db_refer_command '\dt '"${SCHEMA_NAME}"'.*' 2>/dev/null | awk -F',' '{ print $2; }' |
   grep -q "^${OUTPUT_DESC_TABLE_NAME}$"; then
  echo "INFO:${0##*/}: table already exists <${ABS_OUTPUT_DESC_TABLE_NAME}>" 1>&2
else
  db_manage_table_command 'CREATE TABLE '"${ABS_OUTPUT_DESC_TABLE_NAME}"' (
    output_id SERIAL,
    output_name TEXT,
    output_type TEXT,
    output_unit TEXT,
    output_description TEXT
  )'

  db_manage_table_command \
    "GRANT SELECT ON TABLE \"${SCHEMA_NAME}\".\"${OUTPUT_DESC_TABLE_NAME}\" TO ${REFER_ROLE_NAME};"
fi

#####################################################################
# Insert input table
#####################################################################

old_input_names=$(
  db_refer_command "SELECT input_name FROM \"${SCHEMA_NAME}\".\"${INPUT_DESC_TABLE_NAME}\"" |
  grep -v '^$' | sort
)

new_input_names=$(
  cat "${JSON_FILE}" | jq -r ".in.[].name" | sort
)

only_old_input_names=$(
  join -1 1 -2 1 -v 1 <(printf '%s\n' "${old_input_names}") <(printf '%s\n' "${new_input_names}")
)

if [ -n "${only_old_input_names}" ]; then
  only_old_input_names_csv=$(printf '%s' "${only_old_input_names}" | tr '\n' ',')
  echo "ERROR:${0##*/}: there are items that exist only on existing database <${only_old_input_names_csv}>" 1>&2
  exit 1
fi

db_manage_table_command "DELETE FROM \"${SCHEMA_NAME}\".\"${INPUT_DESC_TABLE_NAME}\"" >/dev/null
db_manage_table_command "SELECT SETVAL ('${SCHEMA_NAME}.${INPUT_DESC_TABLE_NAME}_input_id_seq', 1, false);" >/dev/null

jq ".in[]" -c "${JSON_FILE}" |
while read -r line
do
  input_name=$(printf '%s\n' "${line}" | jq -r ".name // empty")
  input_type=$(printf '%s\n' "${line}" | jq -r ".type // empty")
  input_unit=$(printf '%s\n' "${line}" | jq -r ".unit // empty")
  input_description=$(printf '%s\n' "${line}" | jq -r ".description // empty")

  input_command=''
  input_command="${input_command} INSERT into \"${SCHEMA_NAME}\".\"${INPUT_DESC_TABLE_NAME}\""
  input_command="${input_command} (input_name,input_type,input_unit,input_description)"
  input_command="${input_command} VALUES"
  input_command="${input_command} ('${input_name}','${input_type}','${input_unit}','${input_description}')"

  db_manage_table_command "${input_command}" >/dev/null
done

#####################################################################
# Insert output table
#####################################################################

old_output_names=$(
  db_refer_command "SELECT output_name FROM \"${SCHEMA_NAME}\".\"${OUTPUT_DESC_TABLE_NAME}\"" |
  grep -v '^$' | sort
)

new_output_names=$(
  cat "${JSON_FILE}" | jq -r ".in.[].name" | sort
)

only_old_output_names=$(
  join -1 1 -2 1 -v 1 <(printf '%s\n' "${old_output_names}") <(printf '%s\n' "${new_output_names}")
)

if [ -n "${only_old_output_names}" ]; then
  only_old_output_names_csv=$(printf '%s' "${only_old_output_names}" | tr '\n' ',')
  echo "ERROR:${0##*/}: there are items that exist only on existing database <${only_old_output_names_csv}>" 1>&2
  exit 1
fi

db_manage_table_command "DELETE FROM \"${SCHEMA_NAME}\".\"${OUTPUT_DESC_TABLE_NAME}\"" >/dev/null
db_manage_table_command "SELECT SETVAL ('${SCHEMA_NAME}.${OUTPUT_DESC_TABLE_NAME}_output_id_seq', 1, false);" >/dev/null

jq ".out[]" -c "${JSON_FILE}" |
while read -r line
do
  output_name=$(printf '%s\n' "${line}" | jq -r ".name // empty")
  output_type=$(printf '%s\n' "${line}" | jq -r ".type // empty")
  output_unit=$(printf '%s\n' "${line}" | jq -r ".unit // empty")
  output_description=$(printf '%s\n' "${line}" | jq -r ".description // empty")

  output_command=''
  output_command="${output_command} INSERT into \"${SCHEMA_NAME}\".\"${OUTPUT_DESC_TABLE_NAME}\""
  output_command="${output_command} (output_name,output_type,output_unit,output_description)"
  output_command="${output_command} VALUES"
  output_command="${output_command} ('${output_name}','${output_type}','${output_unit}','${output_description}')"

  db_manage_table_command "${output_command}" >/dev/null
done
