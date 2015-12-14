#!/bin/sh

set -e

ROOT="$PWD"

REDIS_VSN="2.8.23"

download_redis() {
	echo "download redis ${REDIS_VSN}..."
	wget -q http://download.redis.io/releases/redis-${REDIS_VSN}.tar.gz
	if [ $? -ne 0 ]; then
    	echo "download redis ${REDIS_VSN} failed"
    	return 1
    fi

	tar xzf redis-${REDIS_VSN}.tar.gz
	mv redis-${REDIS_VSN} redis
	return $?
}

case "$1" in
    clean)
	rm -rf $ROOT/c_src/redis
        ;;

    get-deps)
	cd c_src

        [ -d redis ] || download_redis
        cd redis

        cd $ROOT
        ;;

    *)
        #build redis and install redis-server and redis.conf to ./priv/redis
		cd $ROOT/c_src/redis && make

		mkdir -p $ROOT/priv/redis
		\cp "$ROOT/c_src/redis/src/redis-server" $ROOT/priv/redis/redis-server

		cd $ROOT
        ;;
esac
