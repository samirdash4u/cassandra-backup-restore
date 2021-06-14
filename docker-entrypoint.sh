#!/bin/bash
set -ex
>/opt/cassandra/conf/cassandra-topology.properties
echo "default=${DATACENTER}:${RACK_NAME}" >> /opt/cassandra/conf/cassandra-topology.properties
ALL_SEEDS="$CASSANDRA_SEEDS"
echo "Adding seeds $ALL_SEEDS"
count=`echo "${CASSANDRA_SEEDS}" | tr ',' '\n' | wc -l`
if [ $count -eq 1 ]; then
	echo "${CASSANDRA_SEEDS}=${DATACENTER}:${RACK_NAME}" >> /opt/cassandra/conf/cassandra-topology.properties
else
	for ip in `echo $CASSANDRA_SEEDS | tr ',' ' '`
	do
		echo "${ip}=${DATACENTER}:${RACK_NAME}"  >> /opt/cassandra/conf/cassandra-topology.properties
	done
fi
sed -ri 's/(- seeds:).*/\1 "'"$CASSANDRA_SEEDS"'"/;s/incremental_backups: false/incremental_backups: true/' /opt/cassandra/conf/cassandra.yaml

cd /opt/cassandra

case "$ACTION" in 
	"list")
		./cassandraBackupRestore.sh -L -H "$CASSANDRA_SEEDS" -P "$JMX_PORT"
		;;
	"backup")
		./cassandraBackupRestore.sh -B -H "$CASSANDRA_SEEDS" -P "$JMX_PORT" -K "$KEYSPACE" -T "$BACKUPTYPE"
		;;
	"restore")
		./cassandraBackupRestore.sh -R -H "$CASSANDRA_SEEDS" -P "$JMX_PORT" -K "$KEYSPACE" -S "$SNAPSHOT" -T "$BACKUPTYPE" -d "/tmp/data" -f "/opt/cassandra/conf/cassandra.yaml" -p $TRNS_PORT
		;;
	"delete")
		./cassandraBackupRestore.sh -D -H "$CASSANDRA_SEEDS" -P "$JMX_PORT" -K "$KEYSPACE" -S "$SNAPSHOT" -T "$BACKUPTYPE"  
		;;
	*)
		echo "Invalid action please configure service/cassandra-backup-restore/action [ list | backup | delete | restore ] "
		exit 1
		;;
esac

