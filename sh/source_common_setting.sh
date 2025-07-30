#!/bin/bash

#####################################################################
# setting 
#####################################################################

THIS_FILE="$(realpath "${BASH_SOURCE[0]}")"
THIS_DIR="$(dirname "${THIS_FILE}")"
TOP_DIR="$(dirname "${THIS_DIR}")"

SETTING_FILE="${TOP_DIR}/common_setting.json"

#####################################################################
# check
#####################################################################

if ! type jq >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: jq command not found" 1>&2
  exit 1 
fi

if [ ! -f "${SETTING_FILE}" ]; then
  echo "ERROR:${0##*/}: setting file not found <${SETTING_FILE}" 1>&2
  exit 1 
fi

#####################################################################
# set
#####################################################################

export_command=$(
  jq -c 'to_entries | .[]' "${SETTING_FILE}" |
  while read -r line
  do
    key=$(printf '%s\n' "${line}" | jq -r '.key')
    val=$(printf '%s\n' "${line}" | jq -r '.value')

    printf 'export %s="%s"\n' "${key}" "${val}"
  done
)

eval "${export_command}"
