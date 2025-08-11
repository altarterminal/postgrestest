#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit () {
  cat <<-USAGE 1>&2
Usage   : ${0##*/}
Options : -d<dir name> -n<output name> -f

Backup the database.

-d: Backup to the <dir name> directory (default: .).
-n: Backup to the <output name> file (default: "database_name"_YYYYmmdd_HHMMSS.txt).
-f: Enable overwrite to the existing file of the same name.
USAGE
  exit 1
}

#####################################################################
# parameter
#####################################################################

opt_d=''
opt_n=''
opt_f='no'

i=1
for arg in ${1+"$@"}
do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -d*)                 opt_d="${arg#-d}"    ;;
    -n*)                 opt_n="${arg#-n}"    ;;
    -f)                  opt_f='yes'          ;;
    *)
      echo "ERROR:${0##*/}: invalid args" 1>&2
      exit 1
      ;;
  esac

  i=$((i + 1))
done

DIR_NAME="${opt_d}"
FILE_NAME="${opt_n}"
IS_OVERWRITE="${opt_f}"

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

THIS_DATE=$(date '+%Y%m%d_%H%M%S')
TEMP_NAME="${TMPDIR:-/tmp}/${0##*/}_${THIS_DATE}_XXXXXX"

#####################################################################
# prepare parameter
#####################################################################

if [ -z "${DIR_NAME}" ]; then
  DIR_NAME='.'
else
  if ! mkdir -p "${DIR_NAME}"; then
    echo "ERROR:${0##*/}: cannot make directory <${DIR_NAME}>" 1>&2
    exit 1
  fi
fi

if [ ! -w "${DIR_NAME}" ]; then
  echo "ERROR:${0##*/}: cannot make file in the directory <${DIR_NAME}>" 1>&2
  exit 1
fi

if [ -z "${FILE_NAME}" ]; then
  FILE_NAME="${DB_NAME}_$(date '+%Y%m%d_%H%M%S').txt"
fi

BACKUP_FILE="${DIR_NAME%/}/${FILE_NAME}"

#####################################################################
# check existing file
#####################################################################

if [ -f "${BACKUP_FILE}" ] && [ "${IS_OVERWRITE}" = 'yes' ]; then
  echo "ERROR:${0##*/}: there existing file <${BACKUP_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# prepare tmp file
#####################################################################

TEMP_FILE="$(mktemp "${TEMP_NAME}")"
trap '[ -e ${TEMP_FILE} ] && rm ${TEMP_FILE}' EXIT

#####################################################################
# backup
#####################################################################

if ! pg_dump "${DB_NAME}" \
    -U "${REFER_ROLE_NAME}" \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    >"${TEMP_FILE}"
then
  echo "ERROR:${0##*/}: backup failed for some reason" 1>&2
  exit 1
fi

cp "${TEMP_FILE}" "${BACKUP_FILE}"
