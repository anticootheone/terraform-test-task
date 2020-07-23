#!/bin/bash

# this is for non-interactive timezone configuration
export DEBIAN_FRONTEND=noninteractive

# exporting database passwords intp the .pgpass file for psql non-interactive usage
echo ${db_address}:${db_port}:${dbname}:${dbadmin}:${db_admin_pwd} >> ~/.pgpass
echo ${db_address}:${db_port}:${dbname}:${dbmanager}:${db_manager_pwd} >> ~/.pgpass
echo ${db_address}:${db_port}:${dbname}:${dbuser}:${db_user_pwd} >> ~/.pgpass
chmod 0600 ~/.pgpass

# creating index.html file
cat >> index.html <<EOF
<h1>Printing previously inserted date into the database</h1>
<br>
EOF

# apply updates
apt-get update -y

# set MSK timezone
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# install psql
apt-get install -y postgresql-client-12

# set MSK timezone in database
psql --host=${db_address} --port=${db_port} --username=${dbmanager} ${dbname} -c "set timezone = 'Europe/Moscow';"

# create table in database
psql --host=${db_address} --port=${db_port} --username=${dbmanager} ${dbname} -c "create table ${db_schema}.${db_table}(id serial primary key, epoch integer, iso8601 varchar(26));"

# grant select permissions for dbuser (tf res psql_grant and psql_default_priv aren't working)
psql --host=${db_address} --port=${db_port} --username=${dbmanager} ${dbname} -c "grant select on all tables in schema ${db_schema} to ${dbuser};"

# insert data in two formats in table
psql --host=${db_address} --port=${db_port} --username=${dbmanager} ${dbname} -c "insert into ${db_schema}.${db_table} (epoch, iso8601) values ($(date +'%s'), '"$(date --iso-8601=seconds)"');"

# simple greedy select from table and awk parser for an output
psql --host=${db_address} --port=${db_port} --username=${dbuser} ${dbname} -c "select * from ${db_schema}.${db_table};" | awk '{if($1 == 1) printf "<h3>The requested values for inserted date are:</h3><br>\n - Unix epoch format: <b>%s</b><br>\n - ISO-8601 format:   <b>%s</b><br>\n", $3, $5}' >> index.html

# drop table after that, because tf won't allow us to destroy scheme with attached table
psql --host=${db_address} --port=${db_port} --username=${dbmanager} ${dbname} -c "drop table ${db_schema}.${db_table};"

nohup busybox httpd -f -p ${http_port} &
