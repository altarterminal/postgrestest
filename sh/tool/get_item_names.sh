#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name>
Options : -i -o -s<serial number>  

Get input item names.
-i or -o option must be specified.

-i: Get input item names.
-o: Get output item names.
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
opt_i='no'
opt_o='no'
opt_s='-1'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -i)                  opt_i='yes'          ;;
    -o)                  opt_o='yes'          ;;
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

if [ "${opt_i}" = 'no' ] && [ "${opt_o}" = 'no' ]; then
  echo "ERROR:${0##*/}: input or output must be specified" 1>&2
  exit 1
fi

if [ "${opt_i}" = 'yes' ] && [ "${opt_o}" = 'yes' ]; then
  echo "ERROR:${0##*/}: you can choose only one of input or output" 1>&2
  exit 1
fi

if ! printf '%s\n' "${opt_s}" | grep -Eq '^-?[0-9]+$'; then
  echo "ERROR:${0##*/}: invalid number specified <${opt_s}>" 1>&2
  exit 1
fi

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"

IS_INPUT="${opt_i}"
SERIAL_NUM="${opt_s}"

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

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
GET_TABLE_NAME_BY_SERIAL="${THIS_DIR}/get_table_name_by_serial.sh"
GET_LAST_TABLE_NAME="${THIS_DIR}/get_last_table_name.sh"

DEVICE_SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

if [ "${IS_INPUT}" = 'yes' ]; then
  ABS_DESC_TABLE_NAME="${DEVICE_SCHEMA_NAME}.${COMMON_INPUT_DESC_TABLE_NAME}"
  COLUMN_NAME='input_name'
else
  ABS_DESC_TABLE_NAME="${DEVICE_SCHEMA_NAME}.${COMMON_OUTPUT_DESC_TABLE_NAME}"
  COLUMN_NAME='output_name'
fi

#####################################################################
# get table name
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

#####################################################################
# get item names
#####################################################################

candidate_names=$(
  db_refer_command "
    SELECT ${COLUMN_NAME} FROM ${ABS_DESC_TABLE_NAME}
    ORDER BY ${COLUMN_NAME}
  "
)
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get name failed" 1>&2
  exit "${exit_code}"
fi

table_column_names=$(
  db_refer_command "
    SELECT column_name FROM information_schema.columns
    WHERE table_name = '${target_table_name}'
    ORDER BY column_name
  "
)
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get table column name failed" 1>&2
  exit "${exit_code}"
fi

target_input_names=$(
  join -1 1 -2 1 -o1.1 \
    <(printf '%s\n' "${candidate_names}") \
    <(printf '%s\n' "${table_column_names}")
)

printf '%s\n' "${target_input_names}"
