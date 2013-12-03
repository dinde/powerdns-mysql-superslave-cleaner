#!/bin/bash

## pdns_cleaner.sh ##
# This script will clean all domains not anymore handled
# by a powerDNS SuperSlave server.
# It works ONLY with mysql backend.
# It's based on default PDNS sql scheme.
# You can crontab this file, there is a backup system embedded.
## ATTENTION: You need to use an external recursor.
## Don't execute this script with your /etc/resolv.conf
## With nameserver 127.0.0.1 (localhost). It just won't work.
## Also don't use one of the other dns declared for your domains.
## Set an external DNS to use this script (ie 8.8.8.8).
# Author: David <david@ows.fr> - http://www.ows.fr
# Date: 01/12/2013: Added an exclusion of comments on configuration parsing
# Version: 1.2
# Licence: WTFPLv2 (More informations on footer)

## Config ##
# Here we set were's the powerdns config file.
PDNS_CONFIG='/etc/powerdns/pdns.conf'
# If debian styled (splitted files ...)
PDNS_CONFIG2='/etc/powerdns/pdns.d/pdns.local.gmysql'
# Here we set the local ip (superslave) (shoud be the server where you exec this script)
#LOCAL_IP='212.37.219.30'
LOCAL_IP=$(grep 'local-address' ${PDNS_CONFIG} | grep -v '#' | cut -f'2' -d'=' | sed -e s'/127.0.0.1//g' -e s'/,//g')
# Here we set our ips ranges of supermasters (Only the 3 first group W.X.Y)
REMOTE_IP='192.168.0 10.10.1 192.168.254 172.76.9'
REMOTE_IP_GREP=$(echo ${REMOTE_IP} | sed 's/\ /+|/g')
# Here we set the mysql TABLE for domains
DOMAINS_TABLE='domains'
# Here we set the mysql TABLE for records
RECORDS_TABLE='records'
# Here we set the path where we'll backup
BACKUP_PATH='/home/pdns_cleaner_backups'
# Here we set the backup name
BACKUP_NAME="mysqldump-$(date '+%F').sql"
# Here we set the retention duration in days
BACKUP_RETENTION='180'
# Here we set the mail adress of the admin to be notified in case of problem with backup of mysql database
MAIL_ADMIN="yourmail@domain.tld"
SUJET="We are not able to do a backup of mysql. Dump looks failing"
MSG="Subject: ${SUJET} \
[pdns_cleaner] on $(hostname) reported some errors while backuping.\
Please check it out."

## Functions ##
# Get mysql conf from /etc/powerdns/pdns.conf (or other files) and put it on variables
get_mysql_config () {
        if [ $(grep 'gmysql-user' ${PDNS_CONFIG} | grep -v '#') = '' ] ; then
	       	PDNS_CONFIG=${PDNS_CONFIG2}
        fi
        SQL_USR=$(grep 'gmysql-user' ${PDNS_CONFIG} | cut -f'2' -d'=' | tr -s ' ')
        SQL_DB=$(grep 'gmysql-dbname' ${PDNS_CONFIG} | cut -f'2' -d'=' | tr -s ' ')
        SQL_PW=$(grep 'gmysql-password' ${PDNS_CONFIG} | cut -f'2' -d'=' | tr -s ' ')
}

## Tests if config is done with this script & if powerdns is realy configured with mysql backend
# Test if we're under mysql backend
validate_backend () {
        if [ $(grep 'launch=gmysql' ${PDNS_CONFIG} | grep -v '#') = '' ] ; then
                echo "Your PowerDNS superslave server isn't configured with a Mysql backend."
                echo "This script is only made to work on Mysql Backend."
                logger "[pdns_cleaner] Attempt to run cleaner on another backend than Mysql ! Exiting ..."
                exit 1
	fi
	# When localhost is in use, it won't drop any domain
	grep '127.0.0.1' /etc/resolv.conf
	RESULT=${?}
	# When local DNS is in use, it won't drop any domain
	grep ${LOCAL_IP} /etc/resolv.conf
	RESULT2={$?}
      	# When using one DNS that handles the domain, it will result an error
	grep -E ${REMOTE_IP_GREP} /etc/resolv.conf
	RESULT3=${?}
	if [ ${RESULT} = '0' ] || [ ${RESULT2} = '0' ] || [ ${RESULT3} = '0' ] ; then
		echo "You can't use this script with a local resolver."
		echo "You can't either use a server that host one of your domains"
		echo "It will result not a single domain drop."
		echo "Please use an external resolver by setting it on /etc/resolv.conf. Exiting ..."
		logger "[pdns_cleaner] Attempt to run with local resolver ! Exiting ..."
		exit 1
	else
                validate_config
        fi
}

# Test variables to check if this script is configured
validate_config () {
        if [ ${LOCAL_IP} = '' ] ; then
                echo "Configuration of this script is not done. Please set the LOCAL_IP IP."
                logger "[pdns_cleaner] Attempt to run unconfigured ! Exiting ..."
                exit 1
        elif [ ${REMOTE_IP} = '' ] ; then
                echo "Configuration of this script is not done. Please set the REMOTE_IP IP"
                logger "[pdns_cleaner] Attempt to run unconfigured ! Exiting ..."
                exit 1
        else
                get_mysql_config
                validate_mysql
        fi
}

# Test if the mysql command needs a pass or not
validate_mysql () {
        if [ $(grep gmysql-password ${PDNS_CONFIG}) != '' ] ; then
                # Test if there is a password set
                if [ ${SQL_PW} != '' ] ; then
                        MYSQL_CMD="mysql --skip-column-name -u${SQL_USR} -p${SQL_PW} ${SQL_DB}"
			MYSQLDUMP_CMD="mysqldump --add-drop-table --allow-keywords -q -c -u${SQL_USR} -p${SQL_PW} ${SQL_DB}"
		else
                        MYSQL_CMD="mysql --skip-column-name -u${SQL_USR} ${SQL_DB}"
			MYSQLDUMP_CMD="mysqldump --add-drop-table --allow-keywords -q -c -u${SQL_USR} ${SQL_DB}"
                fi
        fi
}

# We backup the actual mysql database
backup_sql () {
	# We test if backup folder exist
	if [ ! -d ${BACKUP_PATH} ] ; then
		mkdir ${BACKUP_PATH}
		logger "[pdns_cleaner] Missing backup folder, creating it: $BACKUP_PATH"
	fi
	# We test if a file with the same name already exists
	if [ -f ${BACKUP_PATH}/${BACKUP_NAME} ] ; then
		mv -f ${BACKUP_PATH}/${BACKUP_NAME} ${BACKUP_PATH}/${BACKUP_NAME}.old
		logger "[pdns_cleaner] A backup named: ${BACKUP_NAME} exist moving ${BACKUP_NAME}.old"
	fi
	# Let's clean old backup if there is some
	find ${BACKUP_PATH} -name 'mysqldump-*' -mtime +${BACKUP_RETENTION} -type f -exec rm -f {} \;
	logger "[pdns_cleaner] Cleaning backups older than ${BACKUP_RETENTION} days"
	# We dump the database into one file
	${MYSQLDUMP_CMD} > ${BACKUP_PATH}/${BACKUP_NAME}
	if [ ${?} != '0' ] ; then
		logger "[pdns_cleaner] Warning: Dump mysql looks failing. Exiting ..."
		echo "We are not able to do a backup of mysql. Please fix it first."
		# Mail notification
		echo ${MSG} | mail "[pdns_cleaner] Not able to backup mysql on $(hostname)" ${MAIL_ADMIN}
		logger "[pdns_cleaner] Notification sent to ${MAIL_ADMIN}"
		exit 1
	else
		gzip ${BACKUP_PATH}/${BACKUP_NAME}
		logger "[pdns_cleaner] ${BACKUP_PATH}/${BACKUP_NAME}.gz created."
	fi
}

# Tests to validate what domain is not anymore handled by our NS
check_ns_list () {
        # Get domains list from mysql
        for i in $(echo "SELECT name from ${DOMAINS_TABLE}" | ${MYSQL_CMD} | grep -v 'in-addr.arpa')
        do
                # Check reply
                TEST=$(host -W5 -t ns ${i} | awk '{print $3}' | head -n1)
                if [ ${TEST} != 'server' ] ; then
                        # Reply is empty cause non existent or error, we delete the domain
                        clean_records_domain ${i}
                else
                        # We test if NS are handled by us
                        host -W5 -t ns ${i} | awk '{print $4}' | while read n
                        do
                                NS_TEST=$(host -W5 ${n} | awk '{print $4}')
                                # Check if master exists on our ip
                                MASTER_TEST=$(echo ${NS_TEST} | grep -E ${REMOTE_IP_GREP})
                                MASTER_RESULT=${?}
                                # Check the slave
                                SLAVE_TEST=$(echo ${NS_TEST} | grep ${LOCAL_IP})
                                SLAVE_RESULT=${?}
                                if [ ${MASTER_RESULT} == '1' ] && [ ${SLAVE_RESULT}  == '1' ] ; then
                                        # Both are in error we delete the records/domains
                                        clean_records_domain ${i}
					# We go out from the loop since we dropped the domain and its records
					exit 0
				fi
                        done
                fi
        done
}

# Drop entries
# Clean records list from mysql for a specific domain passed with $1
clean_records_domain () {
        # We need to get the id for a domain
        DOMAIN_ID=$(echo "SELECT id from ${DOMAINS_TABLE} where name='${1}'" | ${MYSQL_CMD})
        # We select all record with that id
        echo "DELETE from ${RECORDS_TABLE} where domain_id='${DOMAIN_ID}'" | ${MYSQL_CMD}
        # We finaly drop the domain
        echo "DELETE from ${DOMAINS_TABLE} where name='${1}'" | ${MYSQL_CMD}
        # We log the drop
	logger "[pdns_cleaner] ${1} and all its records removed from our Mysql database"
        # We increment 1 hit on count
        let COUNT_DEL_DOM=${COUNT_DEL_DOM}+1
}

# Build summary with various stats
summary () {
        # If domains count = 1 it means nothing has been deleted we set variable to 0 for summary
        if [ ${COUNT_DEL_DOM} == '1' ] ; then
        	COUNT_DEL_DOM='0'
        fi
        # We get total records after cleaning
        COUNT_DEL_REC=$(echo "SELECT name from ${RECORDS_TABLE}" | ${MYSQL_CMD} | wc -l)
        # We substract actual records from initial total records
        let COUNT_DEL_REC=${COUNT_TOTAL_REC}-${COUNT_DEL_REC}
        # We log it
        logger "[pdns_cleaner] Summary domains: ${COUNT_DEL_DOM} on ${COUNT_TOTAL_DOM} domains deleted"
        logger "[pdns_cleaner] Summary records: ${COUNT_DEL_REC} on ${COUNT_TOTAL_REC} records deleted"
}

##############
## Run It ! ##
##############
logger "[pdns_cleaner] Starting DNS cleaning process: $(date)"
validate_backend
backup_sql
## Misc for counts/summary
# Count start increment
COUNT_DEL_DOM='1'
# We get total domains
COUNT_TOTAL_DOM=$(echo "SELECT name from ${DOMAINS_TABLE}" | ${MYSQL_CMD} | grep -v 'in-addr.arpa' | wc -l)
# We get total records
COUNT_TOTAL_REC=$(echo "SELECT name from ${RECORDS_TABLE}" | ${MYSQL_CMD} | wc -l)
##
check_ns_list
summary
logger "[pdns_cleaner] End of DNS cleaning process: $(date)"
##############
### End ! ####
##############
