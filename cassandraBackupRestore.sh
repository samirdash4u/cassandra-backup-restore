#!/bin/sh 

# Written By	: samir.r@healtechsoftware.ai
# Reviewed By	: 
# Date		: 17-Feb-2021
# Inputs	: -h <help message>
#		: -L <list snapshots>
#		: -B <take backup> 
#		: -b <backup count to retain>
#		: -R <restore from backup>
#		: -H <cassandra ip address>
#		: -f <cassandra file path>
#		: -P <jmx port>
#		: -p <transport port>
#		: -K <keyspace name> 
#		: -S <Snapshot name to restore> 
#		: -T <full/incremental>
# Options	:
#		: List backups
#		: Take full backup
#		: Take incremental backups
#		: Delete backup
#		: Restore both full and incremental backups

BASEDIR=$(readlink -f $(dirname $0))
today=`date "+%Y-%m-%d"`
LOGDIR="$BASEDIR/logs/$today"
TMPDIR="$BASEDIR/tmp"
LOGFILE="$LOGDIR/cassandraBackupRestore.log"
PATH=$PATH:$BASEDIR/binary/bin
CASSANDRA_CONF="$BASEDIR/conf"
CASSANDRA_HOME="$BASEDIR/binary"
CASSANDRA_DATA_DIR="/var/lib/cassandra"
export CASSANDRA_CONF CASSANDRA_HOME NOMAD_MEMORY_LIMIT PATH
if [ -z "$LOG_ENABLE" ]; then
	LOG_ENABLE=1
fi
if [ "$LOG_ENABLE" -eq 1 ]; then
	mkdir -p $LOGDIR
fi
mkdir -p $TMPDIR
logit()
{
	if [ "$LOG_ENABLE" -eq 1 ]; then
		echo "`date "+%Y-%m-%d %H:%M:%S"` : $*" >> $LOGFILE
	fi
}

exit_script(){
	rm -rf $TMPDIR
	find $BASEDIR/logs/ -mtime +5 -type d -exec rm -rf {} \;
	logit "---------- Script execution completed-----------"
	exit $1
}

logit "--------------- Script execution started --------------"


usage()
{
	echo -e "$0 {-h|-H|-L|-B|-R|-D|-d|-f|-P|-p|-K|-S|-T}
\t -h print this help message
\t -L list available snapshots/backup
\t -B initialte backup
\t -b number of backup to retain
\t -R restore from existing backup
\t -D delete given snapshot
\t -d directory where cassandra backup files are present. [ from where restore will happen ]
\t -H cassandra ip address [ default localhost ]
\t -f cassandra.yaml file path [ mandatory in case of restoring ]
\t -P jmx port [ default 11108 ]
\t -p transport port [ default 9142 ]
\t -K keyspace name [ mandatory while creating/restoring backup ]
\t -S Snapshot name to restore [ mandatory while restoring/deleting backup. ]
\t -T full/incremental [ Full backup or incremental backup ]
 
\t Sample commands:
\t 1. Take full backup
\t $0 -H 192.168.13.225 -P 11108 -B -K test -T full
\t 2. Take incremental backup
\t $0 -H 192.168.13.225 -P 11108 -B -K test -T incremental
\t 3. List existing backups
\t $0 -L
\t 4. Delete existing backup
\t $0 -D -S 10_02_2020_test [ to remove single backup, multiple backup names can be provided comma separated ]
\t $0 -D -S all	[ to remove all backups ] 
\t $0 -D -b n [ keep last n backup and remove rest]
\t 5. Restore from backup
\t $0 -H 192.168.13.225 -P 11108 -p 9142 -R -K test -S 10_02_2020_test"
}

while getopts "hH:LBRDb:d:f:P:p:K:S:T:" opt;
do
	case "$opt" in
		h)
			usage
			exit_script 0
			;;
		H)
			cassandraIp=${OPTARG}
			;;
		L)
			sAction="list"
			;;
		B)
			sAction="backup"
			;;
		b)
			BACKUP_COUNT=${OPTARG}
			;;
		R)
			sAction="restore"
			;;
		D)
			sAction="delete"
			;;
		d)
			backupDir=${OPTARG}
			;;
		P)
			jmxPort=${OPTARG}
			;;
		p)
			trnsPort=${OPTARG}
			;;
		K)
			keySpace=${OPTARG}
			;;
		S)
			snapshotName=${OPTARG}
			;;
		T)
			backupType=${OPTARG}
			;;
		f)
			configPath=${OPTARG}
			;;
		*)
			logit "Invalid Input"
			exit_script 1
			;;
	esac
done
shift $((OPTIND -1))

# check if cassandra data dir is available or not
if [ ! -d "$CASSANDRA_DATA_DIR/data/test" ]; then
	logit "$CASSANDRA_DATA_DIR not found. Can not proceed"
	exit_script 1
fi

if [ -z "$sAction" ]; then
	usage
	exit_script 0
fi
if [ -z "$cassandraIp" ]; then
	logit "Cassandra host not provided. Considering default host localhost"
	cassandraIp="localhost"
else
	logit "Cassandra host : $cassandraIp"
fi

if [ -z "$jmxPort" ]; then
	logit "JMX port not provided. Considering default port 11108"
	jmxPort="11108"
else
	logit "Cassandra JMX port : $jmxPort"
fi

if [ -z "$trnsPort" ]; then
	logit "Transport port not provided. Considering default 9142"
	trnsPort="9142"
else
	logit "Transport port : $trnsPort"
fi

if [ -z "$keySpace" ]; then
	logit "keyspace name not provided. Considering default keyspace test"
	keySpace="test"
else
	logit "Keyspace : $keySpace"
fi

if [ -z "$BACKUP_COUNT" ]; then
	logit "Backup count(how many older backups to retain) is not provided. Considering default count as 5"
	BACKUP_COUNT=5
else
	logit "Backup Count : $BACKUP_COUNT"
fi

if [ -z "$backupDir" ]; then
	logit "Backup directory not specified. Can not continue with backup/restore."
	echo "Backup directory not specified. Can not continue with backup/restore."
	exit_script 1
else
	if [ ! -d "$backupDir" ]; then
		logit "Backup dir [ $backupDir ] doesn't exist. Exiting"
		echo "Backup dir [ $backupDir ] doesn't exist. Exiting"
		exit_script 1
	fi
fi

if [ -z "$backupType" ]; then
	logit "Backup Type is empty. considering default backuptype is incremental"
	backupType="incremental"
else
	logit "Backup type is : $backupType"
fi

if [ -z "$NOMAD_TASK_NAME" ]; then
	logit "Running out of nomad"
	NOMAD_TASK_NAME=`hostname`
	logit "Considering node name as $NOMAD_TASK_NAME" 
fi
# check if cassandra is reachable ?
check_cassandra()
{
	output=`nodetool -h $cassandraIp -p $jmxPort status 2>&1`
	echo "$output" | grep -q "Connection refused\|NoRouteToHostException"
	if [ $? -eq 0 ]; then
		logit "Invalid host or port $cassandraIp:$jmxPort"
		echo "Invalid host or port $cassandraIp:$jmxPort"
		return 1
	else
		return 0
	fi
}

# list the available backups
list_backups()
{
	cd $backupDir/$NOMAD_TASK_NAME/
	output=`ls -lrt | awk '{print $NF}'`
	if [ "x$output" == "x" ]; then
		logit "No backups found"
		echo "No backups found"
	else
		echo "$output"
		logit "List of backups for $cassandraIp: -"
		logit "$output"
	fi
}

# delete the backups
delete_backups()
{
	if [ -z "$snapshotName" ]; then
		logit "Backup name not provided. Keeping last $BACKUP_COUNT generated snapshots and deleting rest"
		torem=`echo "$BACKUP_COUNT" 2 | awk '{print $1+$2}'`
		cd $backupDir/$NOMAD_TASK_NAME/
		for file in `ls -lt | awk '{print $NF}' | tail -n +{$torem}`
		do
			logit "Removing backup ${file} from $backupDir/$NOMAD_TASK_NAME/"
			rm -rf $file
		done
		exit_script 1
	fi
	if [ $snapshotName == "all" ]; then
		logit "Deleting all backups from $backupDir/$NOMAD_TASK_NAME/"
		rm -f $backupDir/$NOMAD_TASK_NAME/*
	else
		for sname in `echo $snapshotName | tr ',' '\n'`
		do
			if [ -d "$backupDir/$NOMAD_TASK_NAME/${sname}" ]; then
				logit "Deleting backup : $sname from $backupDir/$NOMAD_TASK_NAME/"
				rm -rf $backupDir/$NOMAD_TASK_NAME/${sname}
			else
				logit "Backup $sname not found in $backupDir/$NOMAD_TASK_NAME/"
			fi
		done
	fi
}

# create a backup with name as YYYY-mm-dd_<keyspace name>
take_backup()
{
	check_cassandra
	if [ $? -ne 0 ]; then
		exit_script 1
	fi
	if [ -z "$backupType" ]; then
		logit "Backup type not provided. Considering incremental backup as default"
		backupType="incremental"
	else
		logit "Backup type : $backupType"
	fi
	if [ -z "$snapshotName" ]; then
		snapshotName="${today}_${keySpace}"
	fi
	if [ "$backupType" == "full" ]; then
		logit "Taking full backup with name $snapshotName"
		output=`nodetool -h $cassandraIp -p $jmxPort snapshot --tag $snapshotName $keySpace 2>&1`
		output="ok"
		echo $output | grep -q "error:" 
		if [ $? -eq 0 ]; then
			logit "Full backup creation failed on $cassandraIp. Reason :"
			logit "$output"
			return 1
		else
			logit "Full backup taken successfully on $cassandraIp:"
			logit "$output"
		fi
		logit "Compressing the full backup ${snapshotName} and storing them in $backupDir"
		BKPDIR=$backupDir/$NOMAD_TASK_NAME/${snapshotName}
		mkdir -p $BKPDIR
		mkdir -p /tmp/$NOMAD_TASK_NAME
		cd $CASSANDRA_DATA_DIR/data
		for folder in `find . -name "$snapshotName"`
		do
			cp -r --parents $folder /tmp/$NOMAD_TASK_NAME/
		done
		cd /tmp
		tar -cJf $BKPDIR/Full.tar.xz $NOMAD_TASK_NAME
		retcode=$?
		cd $BASEDIR
		if [ $retcode -eq 0 ]; then
			logit "Created tar for ${snapshotName} backup in the path $BKPDIR/Full.tar.xz"
			rm -rf /tmp/$NOMAD_TASK_NAME
		else
			logit "Tar creation failed"
		fi
		logit "Removing full backup ${snapshotName} from cassandra data dir"
		noutput=`nodetool -h $cassandraIp -p $jmxPort clearsnapshot -t ${snapshotName} -- $keySpace 2>&1`
		echo $noutput
		logit "$noutput"
	elif [ "$backupType" == "incremental" ]; then
		latestBkpFldr=`ls -lrt $backupDir/$NOMAD_TASK_NAME/ | tail -1 | awk '{print $NF}'`
		if [ "$latestBkpFldr" == "0" ]; then
			logit "No full backup found. Can't continue with incremental backup"
			return 1
		fi
		BKPDIR="$backupDir/$NOMAD_TASK_NAME/$latestBkpFldr"
		output=`nodetool -h $cassandraIp -p $jmxPort flush $keySpace 2>&1`
		if [ $? -ne 0 ]; then
			logit "Incremental backup creation failed on $cassandraIp. Reason :"
			logit "$output"
			return 1
		else
			logit "Incremental backup taken successfully on $cassandraIp:"
			logit "$output"
		fi
		logit "Compressing the incremental backups and storing them in $backupDir"
		mkdir -p /tmp/$NOMAD_TASK_NAME
		cd $CASSANDRA_DATA_DIR/data
		for folder in `find . -name "backups" | grep "/$keySpace/"`
		do
			cp -r --parents $folder /tmp/$NOMAD_TASK_NAME/
		done
		cd /tmp
		tar -cJf $BKPDIR/${today}.tar.xz $NOMAD_TASK_NAME
		retcode=$?
		cd $BASEDIR
		if [ $retcode -eq 0 ]; then
			logit "Created tar for incrementals backups on ${today} in the path $BKPDIR/${today}.tar.xz"
			rm -rf /tmp/$NOMAD_TASK_NAME
		else
			logit "Tar creation failed"
		fi
		logit "Removing incremental backups for ${today} from cassandra data dir"
		noutput=`rm -f $CASSANDRA_DATA_DIR/data/${keySpace}/*/backups/*`
		echo $noutput
		logit "$noutput"
	else
		logit "Invalid backuptype specified : $backupType"
		exit_script 1
	fi
}

# uncompress the required tar file and restore into cassandra
restore_backup()
{
	check_cassandra
	if [ $? -ne 0 ]; then
		exit_script 1
	fi
	if [ -z "$configPath" ]; then
		logit "Cassandra.yaml file is not provided"
		echo "Cassandra.yaml file is not provided"
		exit_script 1
	else
		if [  ! -f "$configPath" ]; then
			logit "$configPath is not present"
			echo "$configPath is not present"
			exit_script 1
		else
			logit "Cassandra.yaml file path is : $configPath "
		fi
	fi
	if [ -z "$snapshotName" ]; then
		logit "Backup name not provided. Can not continue"
		echo "Backup name not provided. Can not continue"
		exit_script 1
	else
		logit "Restoring backup from ${snapshotName}"
	fi
	BKPDIR="$backupDir/$NOMAD_TASK_NAME/${snapshotName}"
	if [ ! -d "${BKPDIR}" ]; then
		logit "Backup ${snapshotName} not found"
		exit_script 1
	fi 
	logit "Creating temp directory for restoring the data"
	mkdir -p $TMPDIR/$keySpace
	mkdir -p $TMPDIR/$snapshotName
	logit "Restoring backup from $backupDir on $cassandraIp"
	for file in `find $backupDir -type f | grep "${snapshotName}"`
	do
		logit "Extracting compressed data from $file to $TMPDIR/$snapshotName/ folder"
		tar -xf $file -C $TMPDIR/$snapshotName/
		for folder in `find $TMPDIR/$snapshotName/ -type d | grep "/snapshots/\|/backups"`
		do
			targetfolder=`echo "$folder" | awk -F "/$keySpace/" '{print $2}'|cut -d '-' -f1`
			logit "Restoring data for table $targetfolder"
			ln -s $folder $TMPDIR/$keySpace/$targetfolder
			if [ "$LOG_ENABLE" -eq 1 ]; then
				sstableloader -f $configPath -d $cassandraIp --port $trnsPort $TMPDIR/$keySpace/$targetfolder | tee -a $LOGFILE 2>&1
			else
				sstableloader -f $configPath -d $cassandraIp --port $trnsPort $TMPDIR/$keySpace/$targetfolder
			fi
			if [ $? -eq 0 ]; then
				logit "Data restored for table $targetfolder"
			else
				logit "Data restore failed for table $targetfolder"
			fi
			unlink $TMPDIR/$keySpace/$targetfolder
		done
		logit "Data restore from backup file $file"
	done
}

# Check the action provided by user
case $sAction in
	"list")
		logit "Getting the list of backups currently available"
		list_backups
		;;
	"delete")
		logit "Deleting provided snapshot"
		delete_backups
		;;
	"backup")
		logit "Taking backup from cassandra"
		take_backup
		;;
	"restore")
		logit "Restoring backup to cassandra"
		restore_backup
		;;
	*)
		logit "Invalid action configured"
		;;
esac
exit_script 0
