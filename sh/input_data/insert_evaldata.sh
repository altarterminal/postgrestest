#!/bin/bash
set -u

#####################################################################
# help
#####################################################################

print_usage_and_exit() {
  cat <<USAGE 1>&2
Usage   : ${0##*/} <project name> <project version> <device name> <file>
Options : -l

Insert evaluation data into the table.
Specify '-' to <file> if its content will be input from standard input.

Command line sample:
  - input evaldata
    - ${0##*/} myproj myver mydev evaldata.json
    - cat evaldata.json | ${0##*/} myproj myver mydev -
  - input list of evaldata file
    - ${0##*/} -l myproj myver mydev evaldata_filelist.txt
    - cat evaldata_filelist.txt | ${0##*/} myproj myver mydev -

Note.
  - evaldata.json can include multiple data in form of json's array.

-l: Specify the evaldata-file-name's list instead of evaldata-file.
-d: Enable dry-run (only judge whether you can insert the data).
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
opt_l='no'
opt_d='no'

i=1
for arg in ${1+"$@"}; do
  case "${arg}" in
    -h|--help|--version) print_usage_and_exit ;;
    -l)                  opt_l='yes'          ;;
    -d)                  opt_d='yes'          ;;
    *)
      if   [ $((i + 3)) -eq $# ] && [ -z "${opr_p}" ]; then
        opr_p="${arg}"
      elif [ $((i + 2)) -eq $# ] && [ -z "${opr_v}" ]; then
        opr_v="${arg}"
      elif [ $((i + 1)) -eq $# ] && [ -z "${opr_n}" ]; then
        opr_n="${arg}"
      elif [ $((i + 0)) -eq $# ] && [ -z "${opr_f}" ]; then
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

if [ -z "${opr_f}" ]; then
  echo "error:${0##*/}: input file must be specified" 1>&2
  exit 1
fi

if [ "${opr_f}" != '-' ]; then
  if [ ! -f "${opr_f}" ] || [ ! -r "${opr_f}" ]; then
    echo "ERROR:${0##*/}: invalid file specified <${opr_f}>" 1>&2
    exit 1
  fi
fi

PROJECT_NAME="${opr_p}"
PROJECT_VERSION="${opr_v}"
DEVICE_NAME="${opr_n}"
INPUT_FILE="${opr_f}"

IS_FILELIST="${opt_l}"
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

THIS_DIR=$(dirname "$(realpath "$0")")
BODY_SCRIPT="${THIS_DIR}/insert_evaldata_body.sh"

THIS_DATE=$(date '+%Y%m%d_%H%M%S')
TEMP_CONTENT_NAME="${TMPDIR:-/tmp}/${0##*/}_${THIS_DATE}_content_XXXXXX"
TEMP_LIST_NAME="${TMPDIR:-/tmp}/${0##*/}_${THIS_DATE}_list_XXXXXX"
TEMP_UNITDATA_NAME="${TMPDIR:-/tmp}/${0##*/}_${THIS_DATE}_unitdata_XXXXXX"

if [ "${IS_DRYRUN}" = 'yes' ]; then
  OPT_DRYRUN='-d'
else
  OPT_DRYRUN=''
fi

#####################################################################
# prepare
#####################################################################

TEMP_CONTENT_FILE="$(mktemp "${TEMP_CONTENT_NAME}")"
TEMP_LIST_FILE="$(mktemp "${TEMP_LIST_NAME}")"
TEMP_UNITDATA_FILE="$(mktemp "${TEMP_UNITDATA_NAME}")"

trap '
  [ -e ${TEMP_CONTENT_FILE} ] && rm ${TEMP_CONTENT_FILE}
  [ -e ${TEMP_LIST_FILE} ] && rm ${TEMP_LIST_FILE}
  [ -e ${TEMP_UNITDATA_FILE} ] && rm ${TEMP_UNITDATA_FILE}
' EXIT

#####################################################################
# prepare
#####################################################################

if [ "${IS_FILELIST}" = 'no' ]; then
  if [ "${INPUT_FILE}" = '-' ]; then
    cat "${INPUT_FILE}" >"${TEMP_CONTENT_FILE}"

    printf '%s\n' "${TEMP_CONTENT_FILE}" >"${TEMP_LIST_FILE}"
  else
    printf '%s\n' "${INPUT_FILE}" >"${TEMP_LIST_FILE}"
  fi
else
  cat "${INPUT_FILE}" |
    tr ',' '\n' | tr ' ' '\n' |
    grep -v '^ *$' | grep -v '^ *#' |
    cat >"${TEMP_LIST_FILE}"
fi

cat "${TEMP_LIST_FILE}" |
  while read -r content_file; do
    if [ ! -f "${content_file}" ] || [ ! -r "${content_file}" ]; then
      echo "ERROR:${0##*/}: invalid file specified <${content_file}>" 1>&2
      exit 1
    fi

    if ! jq . "${content_file}" >/dev/null 2>&1; then
      echo "ERROR:${0##*/}: not follow the JSON format <${content_file}>" 1>&2
      exit 1
    fi
  done

#####################################################################
# insert each data
#####################################################################

cat "${TEMP_LIST_FILE}" |
  while read -r content_file; do
    is_list=$(jq 'type == "array"' "${content_file}")

    if [ "${is_list}" = 'true' ]; then
      jq -c '.[]' "${content_file}"
    else
      jq -c '.' "${content_file}"
    fi |
      while read -r unit_data; do
        printf '%s\n' "${unit_data}" >"${TEMP_UNITDATA_FILE}"

        if ! "${BODY_SCRIPT}" ${OPT_DRYRUN} \
          "${PROJECT_NAME}" "${PROJECT_VERSION}" "${DEVICE_NAME}" \
          "${TEMP_UNITDATA_FILE}"; then
          printf "ERROR:${0##*/}: insert failed <%s,%s>" \
            "${content_file}" "${unit_data}" 1>&2
          exit 1
        fi
      done
  done
