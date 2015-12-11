#!/usr/bin/env bash

TESTDIR="$PWD"
ROOT=`dirname ${TESTDIR}`
HOSTNAME=`hostname`

generate_spec() {
	echo "{node, a, 'a@${HOSTNAME}'}." >> spec
	echo "{node, b, 'b@${HOSTNAME}'}." >> spec

	echo "{alias, test_dir, \"./\"}." >> spec

	echo "{init, [a,b], [{node_start, [{monitor_master, true}, {kill_if_fail, true}, {erl_flags, \"-config ${TESTDIR}/app.config -pa ${ROOT}/ebin -pa ${ROOT}/deps/*/ebin\"}]}]}." >> spec

	echo "{logdir, master, \"./logs/\"}." >> spec
	echo "{logdir, \"./logs/\"}." >> spec

	echo "{config, \"${TESTDIR}/test.config\"}." >> spec

	echo "{groups, [a], test_dir, redis_proxy_replica_SUITE, responser}." >> spec
	echo "{groups, [b], test_dir, redis_proxy_replica_SUITE, requester}." >> spec
}

generate_config() {
	echo "{master_node, 'ct@127.0.0.1'}." >> test.config
	echo "{data_size, 10000}." >> test.config

	echo "{redis_conf_path, \"${ROOT}/priv/redis/redis.conf\"}." >> test.config
	echo "{redis_server_path, \"${ROOT}/priv/redis/redis-server\"}." >> test.config
}

mkdir -p logs

[ -f spec ] && rm spec
generate_spec
[ -f test.config ] && rm test.config
generate_config