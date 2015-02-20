#!/bin/bash
# from Red Hat
# https://access.redhat.com/articles/1232123
# add check for timeout because the RHEL 5.6 boxes do not have it installed and no valid "yum provides timeout" results
which timeout &>/dev/null
if [ $? == 0 ]
then
  ret=$(echo Q | timeout 5 openssl s_client -connect "${1-`hostname`}:${2-443}" -ssl3 2> /dev/null)
else
  ret=$(echo Q | openssl s_client -connect "${1-`hostname`}:${2-443}" -ssl3 2> /dev/null)
fi

if echo "${ret}" | grep -q 'Protocol.*SSLv3'; then
  if echo "${ret}" | grep -q 'Cipher.*0000'; then
    echo "SSL 3.0 disabled"
  else
    echo "SSL 3.0 enabled"
 fi
else
  echo "SSL disabled or other error"
fi
