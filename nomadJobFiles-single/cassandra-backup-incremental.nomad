job "cassandra-backup-incremental" {
	region = "India"
	datacenters = ["dc1"]
	type = "batch"
	task "cassandra-node1" {
		driver = "docker"

		constraint {
			attribute = "${attr.unique.network.ip-address}"
			value = "192.168.13.224"
		}
		artifact {
			source = "https://rhel-224.test:8090/cassandra-backup_1.0.tar"
		}

		template {
			data = <<EOH
				CASSANDRA_SEEDS="{{key "service/cassandra/node1/CASSANDRA_BROADCAST_ADDRESS"}}"
				DATACENTER="{{key "service/cassandra/datacenter"}}"
				RACK_NAME="{{key "service/cassandra/rack"}}"
				ACTION="backup"
				JMX_PORT="{{key "service/cassandra/node1/jmx_port"}}"
				KEYSPACE="{{key "service/cassandra-backup-restore/database-name"}}"
				SNAPSHOT="{{key "service/cassandra-backup-restore/snapshot-name"}}"
				BACKUPTYPE="incremental"
				LOG_ENABLE="{{key "service/cassandra-backup-restore/log-enable"}}"
			EOH

			destination = "secrets/file.env"
			env = true
		}

		config {
			load = "cassandra-backup_1.0.tar"
			image = "cassandra-backup:1.0"
			network_mode="bridge"
	
			volumes = [
				"/opt/test/centeralized_logs/cassandra-backup-restore:/opt/cassandra/logs",
				"/opt/test/test_Service/data/cert/test-truststore.jks:/etc/cassandra/test-truststore.jks",
				"/opt/test/test_Service/data/cert/test-keystore.jks:/etc/cassandra/test-keystore.jks",
				"/opt/test/test_Service/data/cassandra:/var/lib/cassandra",
				"/opt/test/test_Service/data/cassandra-backups:/tmp/data"
			]
		}
		resources {
			cpu = 500
			memory = 524
		}	

	}
}
