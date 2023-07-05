You can download the script and cassandra.tar and start using it. The script expects cassandra is running over ssl.

If there is a requirement to use it with cassandra non ssl, please raise a ticket. i will address the same.

Usage 
	 /usr/bin/bash cassandraBackupRestore.sh {-h|-H|-L|-B|-R|-D|-d|-f|-P|-p|-K|-S|-T}
         -h print this help message
         -L list available snapshots/backup
         -B initialte backup
         -b number of backup to retain
         -R restore from existing backup
         -D delete given snapshot
         -d directory where cassandra backup files are present. [ from where restore will happen ]
         -H cassandra ip address [ default localhost ]
         -f cassandra.yaml file path [ mandatory in case of restoring ]
         -P jmx port [ default 11108 ]
         -p transport port [ default 9142 ]
         -K keyspace name [ mandatory while creating/restoring backup ]
         -S Snapshot name to restore [ mandatory while restoring/deleting backup. ]
         -T full/incremental [ Full backup or incremental backup ]

         Sample commands:
         1. Take full backup
         /usr/bin/bash cassandraBackupRestore.sh -H 192.168.13.225 -P 11108 -B -K test -T full
         2. Take incremental backup
         /usr/bin/bash cassandraBackupRestore.sh -H 192.168.13.225 -P 11108 -B -K test -T incremental
         3. List existing backups
         /usr/bin/bash cassandraBackupRestore.sh -L
         4. Delete existing backup
         /usr/bin/bash cassandraBackupRestore.sh -D -S 10_02_2020_test [ to remove single backup, multiple backup names can be provided comma separated ]
         /usr/bin/bash cassandraBackupRestore.sh -D -S all[ to remove all backups ]
         /usr/bin/bash cassandraBackupRestore.sh -D -b n [ keep last n backup and remove rest]
         5. Restore from backup
         /usr/bin/bash cassandraBackupRestore.sh -H 192.168.13.225 -P 11108 -p 9142 -R -K test -S 10_02_2020_test
