#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit() {
  cat <<USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <image_md5sum> <realdevice_serial>
Options : -d

Insert an environment template into the table.

-d: Enable dry-run (only judge whether you can insert/update the data).
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr_p=''
opr_v=''
opr_i=''
opr_r=''
opt_d='no'

i=1
for arg in ${1+"$@"}; do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -d)                  opt_d='yes'          ;;
    *)
      if   [ $((i + 3)) -eq $# ] && [ -z "${opr_p}" ]; then
        opr_p="${arg}"
      elif [ $((i + 2)) -eq $# ] && [ -z "${opr_v}" ]; then
        opr_v="${arg}"
      elif [ $((i + 1)) -eq $# ] && [ -z "${opr_i}" ]; then
        opr_i="${arg}"
      elif [ $((i + 0)) -eq $# ] && [ -z "${opr_r}" ]; then
        opr_r="${arg}"
      else
        echo "ERROR:${0##*/}: invalid args" 1>&2
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

if ! printf '%s\n' "${opr_i}" | grep -Eq '^[0-9a-f]{32}$'; then
  echo "ERROR:${0##*/}: invalid string for md5sum <${opr_i}>" 1>&2
  exit 1
fi

if ! printf '%s\n' "${opr_r}" | grep -Eq '^[0-9a-f]{8}$'; then
  echo "ERROR:${0##*/}: invalid string for Android Serial <${opr_r}>" 1>&2
  exit 1
fi

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
IMAGE_MD5SUM="${opr_i}"
REALDEVICE_SERIAL="${opr_r}"

IS_DRYRUN="${opt_d}"

#####################################################################
# common setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "$0")")
SETTING_FILE="${THIS_DIR}/../enable_sh_setting.sh"

if [ ! -f "${SETTING_FILE}" ]; then
  echo "ERROR:${0##*/}: setting file not found <${SETTING_FILE}>" 1>&2
  exit 1
fi

. "${SETTING_FILE}"

#####################################################################
# setting
#####################################################################

COMMON_SCHEMA_NAME="${COMMON_COMMON_SCHEMA_NAME}"

IMAGE_TABLE_NAME="${COMMON_IMAGE_TABLE_NAME}"
REALDEVICE_TABLE_NAME="${COMMON_REALDEVICE_TABLE_NAME}"
ENV_TEMPLATE_TABLE_NAME="${COMMON_ENV_TEMPLATE_TABLE_NAME}"

ABS_IMAGE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${IMAGE_TABLE_NAME}"
ABS_REALDEVICE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${REALDEVICE_TABLE_NAME}"
ABS_ENV_TEMPLATE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${ENV_TEMPLATE_TABLE_NAME}"

#####################################################################
# check the image
#####################################################################

image_id=$(
  db_refer_command \
    "SELECT image_id FROM ${ABS_IMAGE_TABLE_NAME}
     WHERE image_md5sum = '${IMAGE_MD5SUM}';"
)

if [ -z "${image_id}" ]; then
  printf 'ERROR:%s: %s <%s>\n' \
    "${0##*/}" \
    'image not registered on image table' \
    "${IMAGE_MD5SUM}" 1>&2
  exit 1
fi

#####################################################################
# check the realdevice
#####################################################################

realdevice_id=$(
  db_refer_command \
    "SELECT realdevice_id FROM ${ABS_REALDEVICE_TABLE_NAME}
     WHERE realdevice_serial = '${REALDEVICE_SERIAL}';"
)

if [ -z "${realdevice_id}" ]; then
  printf 'ERROR:%s: %s <%s>\n' \
    "${0##*/}" \
    'realdevice not registered on realdevice table' \
    "${REALDEVICE_SERIAL}" 1>&2
  exit 1
fi

#####################################################################
# check the existing record
#####################################################################

existing_record=$(
  db_refer_command \
    "SELECT * FROM ${ABS_ENV_TEMPLATE_TABLE_NAME}
     WHERE project_name = '${PROJECT_NAME}'
     AND project_version = '${PROJECT_VERSION}';"
)

if [ -n "${existing_record}" ]; then
  # Check the user's intension
  echo '~~~ Existing Record from here'
  printf '%s\n' "${existing_record}"
  echo '~~~ Existing Record to here'
  echo ''
  printf '%s' 'There existing record above. Do you want to overwrite it? [Y/n] '

  read -r user_input

  if [ "${user_input}" != 'Y' ]; then
    echo "Your input is <${user_input}>. Nothing is done."
    exit
  fi

  IS_INSERT='no'
else
  IS_INSERT='yes'
fi

#####################################################################
# register or dry-run
#####################################################################

if [ "${IS_INSERT}" = 'yes' ]; then
  insert_command=$(
    cat <<____EOF | sed 's! *!!'
    INSERT INTO ${ABS_ENV_TEMPLATE_TABLE_NAME}
    (project_name, project_version, image_md5sum, realdevice_serial)
    VALUES
    ('${PROJECT_NAME}','${PROJECT_VERSION}','${IMAGE_MD5SUM}','${REALDEVICE_SERIAL}')
____EOF
  )

  if [ "${IS_DRYRUN}" = 'yes' ]; then
    printf 'You can insert the data into <%s>.\n' "${ABS_ENV_TEMPLATE_TABLE_NAME}"
    echo '~~~ Insert Command from here'
    printf '%s\n' "${insert_command}"
    echo '~~~ Insert Command to here'
  else
    db_manage_table_command "${insert_command}"
  fi
else
  update_command=$(
    cat <<____EOF | sed 's! *!!'
    UPDATE ${ABS_ENV_TEMPLATE_TABLE_NAME}
    SET (image_md5sum, realdevice_serial) = ('${IMAGE_MD5SUM}','${REALDEVICE_SERIAL}')
    WHERE (project_name, project_version) IN (('${PROJECT_NAME}','${PROJECT_VERSION}'))
____EOF
  )

  if [ "${IS_DRYRUN}" = 'yes' ]; then
    printf 'You can update the data on <%s>.\n' "${ABS_ENV_TEMPLATE_TABLE_NAME}"
    echo '~~~ Update Command from here'
    printf '%s\n' "${update_command}"
    echo '~~~ Update Command to here'
  else
    db_manage_table_command "${update_command}"
  fi
fi
