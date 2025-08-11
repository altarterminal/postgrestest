#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name> <file>
Options : -d

Create an evaluation data table.

-d: Enable dry-run (only judge whether you can create the table).
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

SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

INPUT_DESC_TABLE_NAME="${COMMON_INPUT_DESC_TABLE_NAME}"
OUTPUT_DESC_TABLE_NAME="${COMMON_OUTPUT_DESC_TABLE_NAME}"

ABS_INPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${INPUT_DESC_TABLE_NAME}"
ABS_OUTPUT_DESC_TABLE_NAME="${SCHEMA_NAME}.${OUTPUT_DESC_TABLE_NAME}"

EVALDATA_TABLE_PREFIX="${COMMON_EVALDATA_TABLE_PREFIX}"

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

TOOL_DIR="${THIS_DIR}/../tool"
GET_LAST_TABLE_NAME="${TOOL_DIR}/get_last_table_name.sh"

PROJ_DIR="${THIS_DIR}/../.."
COMMON_ITEM_JSON_FILE="${PROJ_DIR}/${COMMON_COMMON_ITEM_JSON_FILE}"

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
    "SELECT input_name FROM ${ABS_INPUT_DESC_TABLE_NAME}
     ORDER BY input_name"
)

only_file_input_names=$(
  join -1 1 -2 1 -v 1 \
    <(printf '%s\n' "${file_input_names}") \
    <(printf '%s\n' "${existing_input_names}")
)

if [ -n "${only_file_input_names}" ]; then
  only_file_input_names_csv=$(printf '%s' "${only_file_input_names}" | tr '\n' ',')

  printf 'ERROR:%s: there are items that exist only on file <%s>\n' \
    "${0##*/}" "${only_file_input_names_csv}" 1>&2
  exit 1
fi

#####################################################################
# Check output names
#####################################################################

file_output_names=$(jq -r '.out[]' "${JSON_FILE}" | sort)

existing_output_names=$(
  db_refer_command \
    "SELECT output_name FROM ${ABS_OUTPUT_DESC_TABLE_NAME}
     ORDER BY output_name"
)

only_file_output_names=$(
  join -1 1 -2 1 -v 1 \
    <(printf '%s\n' "${file_output_names}") \
    <(printf '%s\n' "${existing_output_names}")
)

if [ -n "${only_file_output_names}" ]; then
  only_file_output_names_csv=$(printf '%s' "${only_file_output_names}" | tr '\n' ',')

  printf 'ERROR:%s: there are items that exist only on file <%s>\n' \
    "${0##*/}" "${only_file_output_names_csv}" 1>&2
  exit 1
fi

#####################################################################
# Get serial
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

prev_serial_num=$(
  printf '%s\n' "${target_table_name}"                              |
  sed 's!^.*_\([0-9][0-9]\)!\1!'                                    |
  sed 's!^0*!!'                                                     |
  {
    # This is needed in case no table has not been created before
    cat; echo '-1';
  }                                                                 |
  grep -v '^$'                                                      |
  sort -n                                                           |
  tail -n 1
)

next_serial_num=$((prev_serial_num + 1))

next_table_name=$(
  printf '%s_%s_%s_%s_%02d\n' \
    "${EVALDATA_TABLE_PREFIX}" \
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

if [ "${IS_DRYRUN}" = 'yes' ]; then
  printf 'You can create the table <%s>.\n' "${abs_next_table_name}"
  echo '~~~ Create Command from here'
  printf '%s\n' "${make_table_command}"
  echo '~~~ Create Command to here'
else
  db_manage_table_command "${make_table_command}"

  db_manage_table_command \
    "GRANT SELECT ON TABLE ${abs_next_table_name} TO ${REFER_ROLE_NAME};"

  printf '%s\n' "${abs_next_table_name}"
fi
