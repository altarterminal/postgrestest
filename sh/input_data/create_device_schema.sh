#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/} <device name>
Options : 

Create device schema.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr=''

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
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

if [ -z "${opr}" ]; then
  echo "ERROR:${0##*/}: device name must be specified" 1>&2
  exit 1
fi

DEVICE_NAME="${opr}"

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

MANAGE_TABLE_ROLE_NAME="${COMMON_MANAGE_TABLE_ROLE_NAME}"
REFER_ROLE_NAME="${COMMON_REFER_ROLE_NAME}"

DEVICE_SCHEMA_NAME="${COMMON_DEVICE_SCHEMA_PREFIX}_${DEVICE_NAME}_${COMMON_DEVICE_SCHEMA_SUFFIX}"

#####################################################################
# Create schema
#####################################################################

if db_refer_command '\dn' | awk -F',' '{ print $1; }' |
   grep -q "^${DEVICE_SCHEMA_NAME}$"; then
  echo "INFO:${0##*/}: schema already exists <${DEVICE_SCHEMA_NAME}>" 1>&2
else
  db_manage_schema_command "CREATE SCHEMA ${DEVICE_SCHEMA_NAME}"

  db_manage_schema_command \
    "GRANT USAGE ON SCHEMA ${DEVICE_SCHEMA_NAME}
     TO ${MANAGE_TABLE_ROLE_NAME},${REFER_ROLE_NAME};"
  db_manage_schema_command \
    "GRANT CREATE ON SCHEMA ${DEVICE_SCHEMA_NAME}
     TO ${MANAGE_TABLE_ROLE_NAME};"
fi
