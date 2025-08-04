#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <SQL statement>
Options : -c

Get evaluation data with SQL.

-c: Enable output in form of CSV.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr=''
opt_c='no'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -c*)                 opt_c="${arg#-c}"    ;;
    *)
      if [ $i -eq $# ] && [ -z "${opr}" ]; then
        opr="${arg}"
      else
        echo "ERROR:${0##*/}: invalid args" 1>&2
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

SQL_STATEMENT="${opr}"

IS_CSV="${opt_c}"

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

REFER_ROLE_NAME="${COMMON_REFER_ROLE_NAME}"

#####################################################################
# get data
#####################################################################

if [ "${IS_CSV}" = 'yes' ]; then
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    --csv \
    -c "${SQL_STATEMENT}"
  )
else
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c "${SQL_STATEMENT}"
  )
fi

exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: SQL query failed" 1>&2
  exit 1
fi

printf '%s\n' "${result}"
