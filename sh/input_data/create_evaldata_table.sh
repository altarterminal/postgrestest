#!/bin/bash
set -eu

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name> <file>
Options : 

Create an evaluation data table.
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

DB_HOST="${COMMON_DB_HOST}"
DB_PORT="${COMMON_DB_PORT}"
DB_NAME="${COMMON_DB_NAME}"

COMMON_ITEM_JSON_FILE="${THIS_DIR}/common.json"

MANAGE_TABLE_ROLE_NAME="${COMMON_MANAGE_TABLE_ROLE_NAME}"
REFER_ROLE_NAME="${COMMON_REFER_ROLE_NAME}"

SCHEMA_NAME="device_${DEVICE_NAME}_schema"

INPUT_DESC_TABLE_NAME="${COMMON_INPUT_DESC_TABLE_NAME}"
OUTPUT_DESC_TABLE_NAME="${COMMON_OUTPUT_DESC_TABLE_NAME}"

ABS_INPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${INPUT_DESC_TABLE_NAME}"
ABS_OUTPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${OUTPUT_DESC_TABLE_NAME}"

TABLE_NAME_PREFIX="eval_${PROJECT_NAME}_${PROJECT_VERSION}_${DEVICE_NAME}"

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
# Check input items
#####################################################################

file_input_names=$(jq -r '.in[]' "${JSON_FILE}" | sort)

existing_input_names=$(
  db_refer_command \
    "SELECT input_name FROM ${ABS_INPUT_DESC_TABLE_NAME}" |
  grep -v '^$' | sort
)

only_file_input_names=$(
  join -1 1 -2 1 -v 1 \
    <(printf '%s\n' "${file_input_names}") \
    <(printf '%s\n' "${existing_input_names}")
)

if [ -n "${only_file_input_names}" ]; then
  only_file_input_names_csv=$(printf '%s' "${only_file_input_names}" | tr '\n' ',')
  echo "ERROR:${0##*/}: there are items that exist only on file <${only_file_input_names_csv}>" 1>&2
  exit 1
fi

#####################################################################
# Check output names
#####################################################################

file_output_names=$(jq -r '.out[]' "${JSON_FILE}" | sort)

existing_output_names=$(
  db_refer_command \
    "SELECT output_name FROM ${ABS_OUTPUT_DESC_TABLE_NAME}" |
  grep -v '^$' | sort
)

only_file_output_names=$(
  join -1 1 -2 1 -v 1 \
    <(printf '%s\n' "${file_output_names}") \
    <(printf '%s\n' "${existing_output_names}")
)

if [ -n "${only_file_output_names}" ]; then
  only_file_output_names_csv=$(printf '%s' "${only_file_output_names}" | tr '\n' ',')
  echo "ERROR:${0##*/}: there are items that exist only on file <${only_file_output_names_csv}>" 1>&2
  exit 1
fi

#####################################################################
# Get serial
#####################################################################

prev_serial_num=$(
  db_refer_command '\dt '"${SCHEMA_NAME}.*"                         |
  awk -F, '{ print $2; }'                                           |
  grep "^${TABLE_NAME_PREFIX}"                                      |
  sed 's!^.*_\([0-9][0-9]\)!\1!'                                    |
  sed 's!^0*!!'                                                     |
  { cat; echo '-1'; }                                               |
  sort -n                                                           |
  tail -n 1
)

next_serial_num=$((prev_serial_num + 1))

next_table_name=$(
  printf 'eval_%s_%s_%s_%02d\n' \
    "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}" \
    "${next_serial_num}"
)

abs_next_table_name="${SCHEMA_NAME}.${next_table_name}"

#####################################################################
# Create command
#####################################################################

make_table_command=$(

{
  # common item #####################################################

  jq -c '.[]' "${COMMON_ITEM_JSON_FILE}"                            |
  while read -r line
  do
    common_name=$(printf '%s\n' "${line}" | jq -r '.name // empty')
    common_type=$(printf '%s\n' "${line}" | jq -r '.type // empty')

    printf '%s %s\n' "${common_name}" "${common_type}"
  done                                                              |
  sed 's!$!,!' | sed 's!^!  !'

  # input item ######################################################

  in_command=$(
    printf 'SELECT %s FROM %s\n' \
      'input_name,input_type' "${ABS_INPUT_DESC_TABLE_NAME}"
  )

  db_refer_command "${in_command}" |
  tr ',' ' ' | sed 's!$!,!' | sed 's!^!  !'

  # output item #####################################################

  out_command=$(
    printf 'SELECT %s FROM %s\n' \
      'output_name,output_type' "${ABS_OUTPUT_DESC_TABLE_NAME}"
  )

  db_refer_command "${out_command}"                                 |
  tr ',' ' ' | sed 's!$!,!' | sed 's!^!  !'
}                                                                   |

sed '$s!,$!!'                                                       |

{
  echo "CREATE TABLE ${abs_next_table_name} ("
  cat
  echo ')'
}
)

#####################################################################
# Create table
#####################################################################

db_manage_table_command "${make_table_command}"

db_manage_table_command \
  "GRANT SELECT ON TABLE ${abs_next_table_name} TO ${REFER_ROLE_NAME};"

printf '%s\n' "${abs_next_table_name}"
