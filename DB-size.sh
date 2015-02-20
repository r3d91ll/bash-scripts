#!/bin/bash

mysql -u root -p -e 'select table_schema as database_name,count(table_name) as table_count,sum(index_length+data_length)/1024/1024 as "size (MB)" from information_schema.tables group by table_schema UNION select "TOTAL" as database_name, count(table_name) as table_count, sum(index_length+data_length)/1024/1024 as "size (MB)" from information_schema.tables;'
