#!/bin/bash
#
# This script configures the couchbase cluster for running.
#
# It uses the couchbase command line tool, docs here:
# http://developer.couchbase.com/documentation/server/current/cli/cbcli-intro.html
#
# Which buckets, how much RAM -- necessary docs are in Sizing Guidelines
# http://developer.couchbase.com/documentation/server/current/install/sizing-general.html
#
#
echo "starting ...."
echo "using client at " `which couchbase-cli`
env

echo "==============================================================="

if [ -z "$ADMIN_LOGIN" ] ; then
   echo "Missing ADMIN_LOGIN"
   exit 1
fi

if [ -z "$ADMIN_PASSWORD" ] ; then
   echo "Missing ADMIN_PASSWORD"
   exit 1
fi

if [ -z "$LOCAL_MODE" ] ; then
   LOCAL_MODE="false"
   echo "LOCAL_MODE not set, setting it to false, this might not work on a local docker environment!"
fi

HOST=localhost
PORT=8091

wait_for_success() {
    "$@"
    while [ $? -ne 0 ]
    do
        echo 'waiting for couchbase to start'
        sleep 2
        "$@"
    done
}

wait_for_healthy() {
    status="beats me"

    QHOST=$HOST
    QPORT=$PORT

    if [ -n "$COUCHBASE_MASTER" ] ; then
        QHOST=$COUCHBASE_MASTER
        QPORT=$PORT ;
    fi

    while [[ "$status" != *"healthy"* ]]
    do
        echo "=========================================================="
        echo "Waiting on couchbase to finish setup and become healthy..."

        # Nasty way to parse json with sed rather than installing
        # extra tools in the VM for this one tiny thing.
        status=`curl -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" http://$QHOST:$QPORT/pools/default 2>/dev/null | sed 's/.*status\"://g' | sed 's/,.*//'`
        echo "Cluster status " $status `date`
        sleep 2
    done

    echo "Healthy"
}

if [ -z "$CLUSTER_RAM_QUOTA" ] ; then
    echo "Missing cluster ram quota, setting to 1024"
    export CLUSTER_RAM_QUOTA=1024 ;
fi

if [ -z "$INDEX_RAM_QUOTA" ] ; then
    echo "Missing index ram quota; setting to 256"
    export INDEX_RAM_QUOTA=256 ;
fi

if [ -z "$FTS_INDEX_RAM_QUOTA" ] ; then
    echo "Missing fts index ram quota; setting to 256"
    export FTS_INDEX_RAM_QUOTA=256 ;
fi

if [ -z "$EVENTING_RAM_QUOTA" ] ; then
    echo "Missing eventing ram quota; setting to 256"
    export EVENTING_RAM_QUOTA=0 ;
fi

if [ -z "$ANALYTICS_INDEX_RAM_QUOTA" ] ; then
    echo "Missing analytics index ram quota; setting to 256"
    export ANALYTICS_INDEX_RAM_QUOTA=0 ;
fi


MY_BUCKET=db

if [ -z "$MY_BUCKET_RAMSIZE" ] ; then
   echo "Missing db bucket ramsize; setting to 256"
   MY_BUCKET_RAMSIZE=256 ;
fi

if [ -z "$SERVICES" ] ; then
   echo "Missing SERVICES, setting them to data,index,query,fts"
   SERVICES=data,index,query,fts ;
fi

echo "Type: $TYPE"

# if this node should reach an existing server (a couchbase link is defined)  => env is set by docker compose link
if [ "$TYPE" = "WORKER" ]; then
    echo "Launching Couchbase Slave Node " $COUCHBASE_NAME " on " $ip
    /entrypoint.sh couchbase-server &

    # echo "Waiting for slave to be ready..."
    wait_for_success curl --silent -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" $ip:$PORT/pools/default -C -

    if [ "$LOCAL_MODE" = "false" ]; then
        echo "!!! THIS SETUP DOESN'T WORK ON LOCAL DOCKER!!!"
        echo "getting IP and setting it as new hostname"

        ip=`hostname -I | cut -d ' ' -f1`

        echo "ip: " $ip
        # this doens't work with couchbase 6.5+ on a local docker setup
        # it has to be 127.0.0.1 not the internal docker ip (internal docker ip is usually not accessible form the local machine)
        # on the other side we need this in a multi machine environment where index, query and data services are on different machines
        # couchbase sends there IP, so it can't be 127.0.0.1 for all of them
        # Rename Node
        echo "Rename Node"
        curl -v -X POST -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" http://127.0.0.1:$PORT/node/controller/rename -d hostname=$ip

    fi

    echo "add worker to the cluster manually atm"
else
    echo "Launching Couchbase..."
    /entrypoint.sh couchbase-server &

    # wait for couchbase to be up
    # This is not sufficient to know that the cluster is healthy and ready to accept queries,
    # but it indicates the REST API is ready to take configuration settings.
    wait_for_success curl --silent -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" $HOST:$PORT/pools/default -C -



    # Initialize Node
    echo "Initialize Node"
    curl -v -X POST -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" http://127.0.0.1:$PORT/nodes/self/controller/settings

    if [ "$LOCAL_MODE" = "false" ]; then
        echo "!!! THIS SETUP DOESN'T WORK ON LOCAL DOCKER!!!"
        echo "getting IP and setting it as new hostname"

        ip=`hostname -I | cut -d ' ' -f1`

        echo "ip: " $ip
        # this doens't work with couchbase 6.5+ on a local docker setup
        # it has to be 127.0.0.1 not the internal docker ip (internal docker ip is usually not accessible form the local machine)
        # on the other side we need this in a multi machine environment where index, query and data services are on different machines
        # couchbase sends there IP, so it can't be 127.0.0.1 for all of them
        # Rename Node
        echo "Rename Node"
        curl -v -X POST -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" http://127.0.0.1:$PORT/node/controller/rename -d hostname=$ip

    fi

    # init the cluster
    # It's very important to get these arguments right, because after
    # a cluster is provisioned, some parameters (like services) cannot
    # be changed.
    echo "Initializing cluster configuration ..."

    couchbase-cli cluster-init --cluster $HOST:$PORT \
        --cluster-username="$ADMIN_LOGIN" \
        --cluster-password="$ADMIN_PASSWORD" \
        --cluster-port=$PORT \
        --cluster-ramsize=$CLUSTER_RAM_QUOTA \
        --cluster-index-ramsize=$INDEX_RAM_QUOTA \
        --services=$SERVICES

    #Check if bucket already exists
    echo "Checking if bucket already exists..."

    couchbase-cli bucket-list -c $HOST \
        -u "$ADMIN_LOGIN" -p "$ADMIN_PASSWORD"
    MY_BUCKET_EXISTS=$(/opt/couchbase/bin/cbstats 127.0.0.1:11210 -b db -u $ADMIN_LOGIN -p $ADMIN_PASSWORD config)

    if [[ ${MY_BUCKET_EXISTS} == *"bucket does not exist"* ]]; then
      echo "bucket does not exist, create one"
      couchbase-cli bucket-create -c $HOST \
              -u "$ADMIN_LOGIN" -p "$ADMIN_PASSWORD" \
              --bucket=$MY_BUCKET \
              --bucket-type=couchbase \
              --bucket-ramsize=$MY_BUCKET_RAMSIZE \
              --wait
    fi

    # For debug purposes in logs, show buckets.
    echo "Inspecting bucket list..."
    couchbase-cli bucket-list -c $HOST \
        -u "$ADMIN_LOGIN" -p "$ADMIN_PASSWORD"

    echo "Inspecting server list..."
    couchbase-cli server-list -c $HOST \
        -u "$ADMIN_LOGIN" -p "$ADMIN_PASSWORD"

    echo "Cluster info after startup..."
    curl --silent -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" http://$HOST:$PORT/pools

    echo "Cluster internal settings after startup..."
    curl --silent -u "$ADMIN_LOGIN:$ADMIN_PASSWORD" http://$HOST:$PORT/internalSettings

    wait_for_healthy

    echo "Finished with cluster setup/config."
    echo `date`
fi

wait
