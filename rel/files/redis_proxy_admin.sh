#!/usr/bin/env bash

RUNNER_SCRIPT_DIR=$(cd ${0%/*} && pwd)
RUNNER_SCRIPT=${0##*/}

RUNNER_BASE_DIR=${RUNNER_SCRIPT_DIR%/*}
RUNNER_ETC_DIR=$RUNNER_BASE_DIR/etc
RUNNER_LOG_DIR=$RUNNER_BASE_DIR/log

# Make sure CWD is set to runner base dir
cd $RUNNER_BASE_DIR

# Extract the target node name from node.args
NAME_ARG=`egrep "^ *-s?name" $RUNNER_ETC_DIR/vm.args`
if [ -z "$NAME_ARG" ]; then
    echo "vm.args needs to have either -name or -sname parameter."
    exit 1
fi

# Learn how to specify node name for connection from remote nodes
echo "$NAME_ARG" | grep '^-sname' > /dev/null 2>&1
if [ "X$?" = "X0" ]; then
    NAME_PARAM="-sname"
    NAME_HOST=""
else
    NAME_PARAM="-name"
    echo "$NAME_ARG" | grep '@.*' > /dev/null 2>&1
    if [ "X$?" = "X0" ]; then
        NAME_HOST=`echo "${NAME_ARG}" | sed -e 's/.*\(@.*\)$/\1/'`
    else
        NAME_HOST=""
    fi
fi

# Extract the target cookie
COOKIE_ARG=`grep '\-setcookie' $RUNNER_ETC_DIR/vm.args`
if [ -z "$COOKIE_ARG" ]; then
    echo "vm.args needs to have a -setcookie parameter."
    exit 1
fi

# Identify the script name
SCRIPT=`basename $0`

# Parse out release and erts info
START_ERL=`cat $RUNNER_BASE_DIR/releases/start_erl.data`
ERTS_VSN=${START_ERL% *}
APP_VSN=${START_ERL#* }

# Add ERTS bin dir to our path
ERTS_PATH=$RUNNER_BASE_DIR/erts-$ERTS_VSN/bin

# Setup command to control the node
NODETOOL="$ERTS_PATH/escript $ERTS_PATH/nodetool $NAME_ARG $COOKIE_ARG"

ensure_node_running()
{
    # Make sure the local node IS running
    RES=`$NODETOOL ping`
    if [ "$RES" != "pong" ]; then
        echo "Node is not running!"
        exit 1
    fi
}

# Check the first argument for instructions
case "$1" in
    join)
        if [ $# -ne 2 ]; then
            echo "Usage: $SCRIPT join <node>"
            exit 1
        fi
        ensure_node_running
        $NODETOOL rpc distributed_proxy join_cluster "$2"
        ;;
    status)
        ensure_node_running
        $NODETOOL rpc distributed_proxy_cli command "dp-admin" "cluster" "status"
        ;;
    replicas)
        if [ $# -eq 1 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_cli command "dp-admin" "cluster" "replicas"
        elif [ $# -eq 2 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_cli command "dp-admin" "cluster" "replicas" "--node" "$2"
        else
            echo "Usage: $SCRIPT replicas [<node>]"
            exit 1
        fi
        ;;
    map)
        ensure_node_running
        $NODETOOL rpc distributed_proxy_cli command "dp-admin" "cluster" "map"
        ;;
    replica)
        if [ $# -eq 2 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_cli command "dp-admin" "cluster" "replica" "--replica" "$2"
        elif [ $# -eq 3 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_cli command "dp-admin" "cluster" "replica" "--replica" "$2" "--node" "$3"
        else
            echo "Usage: $SCRIPT replica <replica_id> [<node>]"
            exit 1
        fi
        ;;
    locate)
        if [ $# -eq 2 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_cli command "dp-admin" "cluster" "locate" "--key" "$2"
        else
            echo "Usage: $SCRIPT locate <key>"
            exit 1
        fi
        ;;
    config)
        if [ $# -eq 2 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_config get $2
        elif [ $# -eq 3 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_config set $2 $3
        else
            echo "Usage: $SCRIPT config <name> [<value>]"
            exit 1
        fi
        ;;
    pause)
        if [ $# -eq 3 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_replica_manager pause_replica $2 $3
        else
            echo "Usage: $SCRIPT pause <replica_id> <replica_index>"
            exit 1
        fi
        ;;
    resume)
        if [ $# -eq 3 ]; then
            ensure_node_running
            $NODETOOL rpc distributed_proxy_replica_manager resume_replica $2 $3
        else
            echo "Usage: $SCRIPT resume <replica_id> <replica_index>"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $SCRIPT join | status | replicas | map | replica | config | pause | resume"
        exit 1
        ;;
esac
