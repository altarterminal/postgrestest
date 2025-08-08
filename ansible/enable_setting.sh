#!/bin/bash

#####################################################################
# setting
#####################################################################

THIS_FILE="$(realpath "${BASH_SOURCE[0]}")"
THIS_DIR="$(dirname "${THIS_DIR}")"
KEY_DIR="${THIS_DIR}/key"
FILES_DIR="${THIS_DIR}/roles/setup_virt_env/files"

CONFIG_FILE="${THIS_DIR}/ansiblg.cfg"
SEC_KEY_FILE="${KEY_DIR}/id_rsa"
PUB_KEY_FILE="${KEY_DIR}/id_rsa.pub"

#####################################################################
# check
#####################################################################

IS_SUCCESS='yes'

if [ ! -f "${SEC_KEY_FILE}" ]; then
  echo "ERROR:${THIS_FILE##/}: secret key not found <${SEC_KEY_FILE}>"
  IS_SUCCESS='no'
fi

if [ ! -f "${PUB_KEY_FILE}" ]; then
  echo "ERROR:${THIS_FILE##/}: secret key not found <${SEC_KEY_FILE}>"
  IS_SUCCESS='no'
fi

#####################################################################
# execute setting
#####################################################################

if [ "${IS_SUCCESS}" = 'yes' ]; then
  mkdir -p "${FILES_DIR}"
  cp "${PUB_KEY_FILE}" "${FILES_DIR%/}/"

  export ANSIBLE_CONFIG="${CONFIG_FILE}"
  export ANSIBLE_PRIVATE_KEY_FILE="${SEC_KEY_FILE}"
fi

#####################################################################
# cleanup
#####################################################################

unset 'THIS_FILE'
unset 'THIS_DIR'
unset 'KEY_DIR'
unset 'FILES_DIR'

unset 'CONFIG_FILE'
unset 'SEC_KEY_FILE'
unset 'PUB_KEY_FILE'

#####################################################################
# return proper exit code
#####################################################################

if [ "${IS_SUCCESS}" = 'yes' ]; then
  unset 'IS_SUCCESS'
  true
else
  unset 'IS_SUCCESS'
  false
fi
