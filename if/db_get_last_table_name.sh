#!/bin/bash
set -u

#####################################################################
# setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
SCRIPT_DIR="${THIS_DIR}/../sh/tool"
SCRIPT_FILE="${SCRIPT_DIR}/get_last_table_name.sh"

if [ ! -f "${SCRIPT_FILE}" ] || [ ! -x "${SCRIPT_FILE}" ]; then
  echo "ERROR:${0##*/}: invalid script specified <${SCRIPT_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# call
#####################################################################

"${SCRIPT_FILE}" "$@"
