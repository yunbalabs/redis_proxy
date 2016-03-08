#!/usr/bin/env bash

ps -ef | grep -e beam -e redis-server | grep redis_proxy |awk '{print $2}'| xargs kill > /dev/null 2>&1
exit 0