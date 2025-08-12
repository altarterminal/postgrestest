#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit() {
  cat <<USAGE 1>&2
Usage   : ${0##*/}
Options :

Check the environment of execution and create required files.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

for arg in ${1+"$@"}; do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    *)
      echo "ERROR:${0##*/}: invalid args" 1>&2
      exit 1
      ;;
  esac
done

#####################################################################
# setting
#####################################################################

THIS_DIR="$(dirname "$(realpath "$0")")"
TOP_DIR="$(dirname "${THIS_DIR}")"

SETTING_FILE="${TOP_DIR}/common_setting.json"
ENABLER_FILE="${THIS_DIR}/enable_sh_setting.sh"

#####################################################################
# check
#####################################################################

if ! type jq >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: jq command not found" 1>&2
  exit 1
fi

if ! type psql >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: psql command not found" 1>&2
  exit 1
fi

if [ ! -f "${SETTING_FILE}" ]; then
  echo "ERROR:${0##*/}: setting file not found <${SETTING_FILE}" 1>&2
  exit 1
fi

#####################################################################
# export parameter
#####################################################################

jq -c 'to_entries | .[]' "${SETTING_FILE}" |
while read -r line
do
  key=$(printf '%s\n' "${line}" | jq -r '.key')
  val=$(printf '%s\n' "${line}" | jq -r '.value')

  printf 'export %s="%s"\n' "${key}" "${val}"
done |
cat >"${ENABLER_FILE}"

echo >>"${ENABLER_FILE}"

#####################################################################
# export function
#####################################################################

cat <<'EOF' >>"${ENABLER_FILE}"
db_check_param_definition() {
  if \
    [ -z "${COMMON_DB_NAME:-}" ] ||
    [ -z "${COMMON_DB_HOST:-}" ] ||
    [ -z "${COMMON_DB_PORT:-}" ] ||
    [ -z "${COMMON_MANAGE_SCHEMA_ROLE_NAME:-}" ] ||
    [ -z "${COMMON_MANAGE_TABLE_ROLE_NAME:-}" ] ||
    [ -z "${COMMON_REFER_ROLE_NAME:-}" ]
  then
    echo "ERROR:${0##*/}: some required variables not defined" 1>&2
    exit 1
  fi
}

db_manage_schema_command() {
  local COMMAND="$1"

  db_check_param_definition

  psql "${COMMON_DB_NAME}" \
    -U "${COMMON_MANAGE_SCHEMA_ROLE_NAME}" \
    -h "${COMMON_DB_HOST}" \
    -p "${COMMON_DB_PORT}" \
    -c "${COMMAND}"
}

db_manage_table_command() {
  local COMMAND="$1"

  db_check_param_definition

  psql "${COMMON_DB_NAME}" \
    -U "${COMMON_MANAGE_TABLE_ROLE_NAME}" \
    -h "${COMMON_DB_HOST}" \
    -p "${COMMON_DB_PORT}" \
    -c "${COMMAND}"
}

db_refer_command() {
  local COMMAND="$1"

  db_check_param_definition

  psql "${COMMON_DB_NAME}" \
    -U "${COMMON_REFER_ROLE_NAME}" \
    -h "${COMMON_DB_HOST}" \
    -p "${COMMON_DB_PORT}" \
    -c "${COMMAND}" \
    -t --csv
}

db_refer_command_default() {
  local COMMAND="$1"

  db_check_param_definition

  psql "${COMMON_DB_NAME}" \
    -U "${COMMON_REFER_ROLE_NAME}" \
    -h "${COMMON_DB_HOST}" \
    -p "${COMMON_DB_PORT}" \
    -c "${COMMAND}"
}
EOF
