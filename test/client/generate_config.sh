#!/usr/bin/env bash

TESTDIR="$PWD"
ROOT=`dirname $(dirname ${TESTDIR})`
HOSTNAME=`hostname`

generate_spec() {
	echo "{node, a, 'a@${HOSTNAME}'}." >> spec
	echo "{node, b, 'b@${HOSTNAME}'}." >> spec

	echo "{alias, test_dir, \"./\"}." >> spec

	echo "{init, [a], [{node_start, [{monitor_master, true}, {kill_if_fail, true}, {erl_flags, \"-config ${TESTDIR}/replica1.config -pa ${ROOT}/ebin -pa ${ROOT}/deps/*/ebin -pa ${ROOT}/test/ebin\"}]}]}." >> spec
	echo "{init, [b], [{node_start, [{monitor_master, true}, {kill_if_fail, true}, {erl_flags, \"-config ${TESTDIR}/replica2.config -pa ${ROOT}/ebin -pa ${ROOT}/deps/*/ebin -pa ${ROOT}/test/ebin\"}]}]}." >> spec

	echo "{logdir, master, \"../logs/\"}." >> spec
	echo "{logdir, \"../logs/\"}." >> spec

	echo "{config, \"${TESTDIR}/test.config\"}." >> spec

	echo "{groups, [a], test_dir, redis_proxy_client_SUITE, responser}." >> spec
	echo "{groups, [b], test_dir, redis_proxy_client_SUITE, requester}." >> spec
}

generate_config() {
	echo "{master_node, 'ct@127.0.0.1'}." >> test.config

	echo "{redis_conf_path, \"${ROOT}/priv/redis/redis.conf\"}." >> test.config
	echo "{redis_server_path, \"${ROOT}/priv/redis/redis-server\"}." >> test.config
	echo "{redis_close_script_path, \"${ROOT}/priv/redis/close_redis.sh\"}." >> test.config
}

[ -f spec ] && rm spec
generate_spec
[ -f test.config ] && rm test.config
generate_config