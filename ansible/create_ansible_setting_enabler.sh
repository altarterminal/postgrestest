#!/bin/bash
set -u

#####################################################################
# setting
#####################################################################

THIS_FILE="$(realpath "${BASH_SOURCE[0]}")"
THIS_DIR="$(dirname "${THIS_FILE}")"
KEY_DIR="${THIS_DIR}/key"
FILES_DIR="${THIS_DIR}/roles/setup_virt_env/files"

CONFIG_FILE="${THIS_DIR}/ansiblg.cfg"
SEC_KEY_FILE="${KEY_DIR}/id_rsa"
PUB_KEY_FILE="${KEY_DIR}/id_rsa.pub"

ENABLER_FILE="${THIS_DIR}/enable_ansible_setting.sh"

#####################################################################
# check
#####################################################################

if [ ! -f "${SEC_KEY_FILE}" ]; then
  echo "ERROR:${THIS_FILE##/}: secret key not found <${SEC_KEY_FILE}>"
  exit 1
fi

if [ ! -f "${PUB_KEY_FILE}" ]; then
  echo "ERROR:${THIS_FILE##/}: secret key not found <${SEC_KEY_FILE}>"
  exit 1
fi

#####################################################################
# locate file
#####################################################################

mkdir -p "${FILES_DIR}"
cp "${PUB_KEY_FILE}" "${FILES_DIR%/}/"

#####################################################################
# export parameter 
#####################################################################

cat <<EOF >"${ENABLER_FILE}"
export ANSIBLE_CONFIG="${CONFIG_FILE}"
export ANSIBLE_PRIVATE_KEY_FILE="${SEC_KEY_FILE}"
