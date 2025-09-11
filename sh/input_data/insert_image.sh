#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit() {
  cat <<USAGE 1>&2
Usage   : ${0##*/} <file>
Options : -d

Insert images into the table.

-d: Enable dry-run (only judge whether you can insert/update the data).
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opr=''
opt_d='no'

i=1
for arg in ${1+"$@"}; do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -d)                  opt_d='yes'          ;;
    *)
      if [ $((i + 0)) -eq $# ] && [ -z "${opr}" ]; then
        opr="${arg}"
      else
        echo "ERROR:${0##*/}: invalid args" 1>&2
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

JSON_FILE="${opr}"

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
ABS_IMAGE_TABLE_NAME="${COMMON_SCHEMA_NAME}.${IMAGE_TABLE_NAME}"

#####################################################################
# check json
#####################################################################

if ! jq . "${JSON_FILE}" >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: invalid json file specified <${JSON_FILE}>" 1>&2
  exit 1
fi

is_array=$(jq 'type == "array"' "${JSON_FILE}")

#####################################################################
# check values
#####################################################################

if [ "${is_array}" = 'true' ]; then
  jq -c '.[]' "${JSON_FILE}"
else
  jq -c '.' "${JSON_FILE}"
fi |
  while read -r line; do
    image_md5sum=$(printf '%s\n' "${line}" | jq -r '.image_md5sum')

    if ! printf '%s\n' "${image_md5sum}" | grep -Eq '^[a-f0-9]{32}$'; then
      echo "ERROR:${0##*/}: invalid md5sum specified <${image_md5sum}>" 1>&2
      exit 1
    fi
  done
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: check value failed" 1>&2
  exit "${exit_code}"
fi

#####################################################################
# get the existing image list
#####################################################################

existing_image_md5sum_list=$(
  db_refer_command "SELECT image_md5sum FROM ${ABS_IMAGE_TABLE_NAME};"
)
exit_code=$?

if [ "${exit_code}" -ne 0 ]; then
  echo "ERROR:${0##*/}: get image md5sum list failed" 1>&2
  exit "${exit_code}"
fi

#####################################################################
# insert or update image
#####################################################################

if [ "${is_array}" = 'true' ]; then
  jq -c '.[]' "${JSON_FILE}"
else
  jq -c '.' "${JSON_FILE}"
fi |
  while read -r line; do
    image_md5sum=$(printf '%s\n' "${line}" | jq -r '.image_md5sum')
    image_relative_path=$(printf '%s\n' "${line}" | jq -r '.image_relative_path')
    image_description_url=$(printf '%s\n' "${line}" | jq -r '.image_description_url')

    if printf '%s\n' "${existing_image_md5sum_list}" | grep -q ^"${image_md5sum}"$; then
      # update
      db_command=$(
        cat <<________EOF | sed 's! *!!'
        UPDATE ${ABS_IMAGE_TABLE_NAME}
        SET (image_relative_path,image_description_url) = ('${image_relative_path}','${image_description_url}')
        WHERE image_md5sum = '${image_md5sum}'
________EOF
      )
    else
      # insert
      db_command=$(
        cat <<________EOF | sed 's! *!!'
        INSERT INTO ${ABS_IMAGE_TABLE_NAME}
        (image_md5sum,image_relative_path,image_description_url)
        VALUES
        ('${image_md5sum}','${image_relative_path}','${image_description_url}')
________EOF
      )
    fi

    if [ "${IS_DRYRUN}" = 'yes' ]; then
      printf 'You can insert or update the data into <%s>.\n' "${ABS_IMAGE_TABLE_NAME}"
      echo '~~~ Command from here'
      printf '%s\n' "${db_command}"
      echo '~~~ Command to here'
    else
      db_manage_table_command "${db_command}"
    fi
  done
