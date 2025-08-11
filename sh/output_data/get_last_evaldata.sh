#!/bin/bash
set -u

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
opt_c='no'
opt_j='no'
opt_s='-1'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -c)                  opt_c='yes'          ;;
    -j)                  opt_j='yes'          ;;
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

IS_CSV="${opt_c}"
IS_JSON="${opt_j}"
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

DB_NAME="${COMMON_DB_NAME}"
DB_HOST="${COMMON_DB_HOST}"
DB_PORT="${COMMON_DB_PORT}"

REFER_ROLE_NAME="${COMMON_REFER_ROLE_NAME}"

DEVICE_SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
TOOL_DIR="${THIS_DIR}/../tool"
GET_TABLE_NAME_BY_SERIAL="${TOOL_DIR}/get_table_name_by_serial.sh"
GET_LAST_TABLE_NAME="${TOOL_DIR}/get_last_table_name.sh"
GET_ITEM_NAMES="${TOOL_DIR}/get_item_names.sh"

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

abs_target_table_name="${DEVICE_SCHEMA_NAME}.${target_table_name}"

#####################################################################
# get input item names
#####################################################################

target_input_names=$(
  ${GET_ITEM_NAMES} -i \
    "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}"
)

exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get item names failed" 1>&2
  exit "${exit_code}"
fi

input_name_tuple=$(
  printf '%s\n' "${target_input_names}" | tr '\n' ',' | sed 's!,$!!'
)

#####################################################################
# get data
#####################################################################

if [ "${IS_JSON}" = 'yes' ]; then
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -t \
    -c "
      SELECT to_json(${target_table_name})
      FROM ${abs_target_table_name}
      WHERE
        ( measure_date, ${input_name_tuple} )
        IN
        (
          SELECT MAX(measure_date), ${input_name_tuple}
          FROM ${abs_target_table_name} 
          GROUP BY ${input_name_tuple}
        )"
  )
elif [ "${IS_CSV}" = 'yes' ]; then
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    --csv \
    -c "
      SELECT *
      FROM ${abs_target_table_name}
      WHERE
        ( measure_date, ${input_name_tuple} )
        IN
        (
          SELECT MAX(measure_date), ${input_name_tuple}
          FROM ${abs_target_table_name} 
          GROUP BY ${input_name_tuple}
        )"
  )
else
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c "
      SELECT *
      FROM ${abs_target_table_name}
      WHERE
        ( measure_date, ${input_name_tuple} )
        IN
        (
          SELECT MAX(measure_date), ${input_name_tuple}
          FROM ${abs_target_table_name} 
          GROUP BY ${input_name_tuple}
        )"
  )
fi

exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get data failed" 1>&2
  exit "${exit_code}"
fi

printf '%s\n' "${result}"
