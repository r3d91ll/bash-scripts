#!/bin/bash
#script to check mysql for broken views

mysql -Bse "select concat('\`', TABLE_SCHEMA, '\`.\`', TABLE_NAME, '\`') from INFORMATION_SCHEMA.TABLES where TABLE_TYPE='VIEW';" > views

for v in `cat views`; do echo $v; mysql -e "select * from $v limit 1;" 1>/dev/null; done &>viewerrors

grep ^ERROR viewerrors
