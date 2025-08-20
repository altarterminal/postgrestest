#!/bin/bash
set -u

#####################################################################
# setting
#####################################################################

THIS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
ANSIBLE_DIR="${THIS_DIR}/../ansible"

INVENTORY_FILE="${ANSIBLE_DIR}/inventory.ini"
SITE_FILE="${ANSIBLE_DIR}/site_setup_virt_env.yml"

#####################################################################
# check
#####################################################################

if ! type ansible >/dev/null 2>&1; then
  echo "ERROR:${0##*/}: ansible command not found" 1>&2
  exit 1
fi

if [ ! -f "${INVENTORY_FILE}" ] || [ ! -r "${INVENTORY_FILE}" ]; then
  echo "ERROR:${0##*/}: invalid inventory specified <${INVENTORY_FILE}>" 1>&2
  exit 1
fi

if [ ! -f "${SITE_FILE}" ] || [ ! -r "${SITE_FILE}" ]; then
  echo "ERROR:${0##*/}: invalid site specified <${SITE_FILE}>" 1>&2
  exit 1
fi

#####################################################################
# call
#####################################################################

ansible-playbook -i "${INVENTORY_FILE}" "${SITE_FILE}"
