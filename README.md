# couchbase-syncgateway-containers

Official docker image for *Sync Gateway* https://hub.docker.com/r/couchbase/sync-gateway

Official docker image for *Couchbase Server* https://hub.docker.com/r/couchbase/server

Run `docker-compose up -d` to start both couchbase and syncgateway containers

To run couchbase server alone use this cmd

`docker run -d --name db -p 8091-8097:8091-8097 -p 9123:9123 -p 11207:11207 -p 11210:11210 -p 11280:11280 -p 18091-18097:18091-18097 ./couchbase`

To run Syncgateway alone use this cmd

`docker run -p 4984-4985:4984-4985 -v ./sync-gateway/sg-config.json:/etc/sync_gateway/config.json -d couchbase/sync-gateway -adminInterface :4985 /etc/sync_gateway/config.json`

