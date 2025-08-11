#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <project name> <project version>
Options : -c -j

Get the environment template data.

-c: Enable output in form of CSV.
-j: Enable output in form of JSON.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr_p=''
opr_v=''
opt_c='no'
opt_j='no'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -c)                  opt_c='yes'          ;;
    -j)                  opt_j='yes'          ;;
    *)
      if   [ $((i+1)) -eq $# ] && [ -z "${opr_p}" ]; then
        opr_p="${arg}"
      elif [ $((i+0)) -eq $# ] && [ -z "${opr_v}" ]; then
        opr_v="${arg}"
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

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"

IS_CSV="${opt_c}"
IS_JSON="${opt_j}"

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

COMMON_SCHEMA_NAME="${COMMON_COMMON_SCHEMA_NAME}"

ENV_TEMPLATE_TABLE_NAME="${COMMON_ENV_TEMPLATE_TABLE_NAME}"

ABS_ENV_TEMPLATE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${ENV_TEMPLATE_TABLE_NAME}"

#####################################################################
# check consistency
#####################################################################

record_num=$(
  db_refer_command \
    "SELECT COUNT(*) FROM ${ABS_ENV_TEMPLATE_TABLE_NAME}
     WHERE (project_name, project_version)
     IN (('${PROJECT_NAME}','${PROJECT_VERSION}'));"
)
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get data failed" 1>&2
  exit "${exit_code}"
fi

if [ "${record_num}" -eq 0 ]; then
  echo "ERROR:${0##*/}: no matched record <${PROJECT_NAME},${PROJECT_VERSION}>" 1>&2
  exit 1
elif [ "${record_num}" -ge 2 ]; then
  echo "ERROR:${0##*/}: something wrong since matched record is more than 1 <${record_num}>" 1>&2
  exit 1
else
  :
fi

#####################################################################
# get environment template
#####################################################################

if [ "${IS_JSON}" = 'yes' ]; then
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -t \
    -c \
    "SELECT to_json(${ENV_TEMPLATE_TABLE_NAME})
     FROM ${ABS_ENV_TEMPLATE_TABLE_NAME}
     WHERE (project_name, project_version)
     IN (('${PROJECT_NAME}','${PROJECT_VERSION}'));"
  )
elif [ "${IS_CSV}" = 'yes' ]; then
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    --csv \
    -c \
    "SELECT *
     FROM ${ABS_ENV_TEMPLATE_TABLE_NAME}
     WHERE (project_name, project_version)
     IN (('${PROJECT_NAME}','${PROJECT_VERSION}'));"
  )
else
  result=$(psql "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" -h "${DB_HOST}" -p "${DB_PORT}" \
    -c \
    "SELECT *
     FROM ${ABS_ENV_TEMPLATE_TABLE_NAME}
     WHERE (project_name, project_version)
     IN (('${PROJECT_NAME}','${PROJECT_VERSION}'));"
  )
fi

exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get environment template failed" 1>&2
  exit "${exit_code}"
fi

printf '%s\n' "${result}"
