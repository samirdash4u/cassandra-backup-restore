FROM adoptopenjdk:8-jre-hotspot-bionic

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
# solves warning: "jemalloc shared library could not be preloaded to speed up memory allocations"
		libjemalloc1 \
# "free" is used by cassandra-env.sh
		procps \
# "cqlsh" needs a python interpreter
		python \
# "ip" is not required by Cassandra itself, but is commonly used in scripting Cassandra's configuration (since it is so fixated on explicit IP addresses)
		iproute2 \
# Cassandra will automatically use numactl if available
		numactl \
	; \
	rm -rf /var/lib/apt/lists/*

COPY ./docker-entrypoint.sh /
COPY ./cassandra.tar /opt/
RUN cd /opt && tar -xvf cassandra.tar && rm -f cassandra.tar

RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

