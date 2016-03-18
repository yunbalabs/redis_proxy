#!/usr/bin/env bash

mkdir -p logs ebin

erl -pz ebin -make || exit 1

TEST_CASE_DIR=(command replica_failover scaleout)

for CASE in ${TEST_CASE_DIR[@]}
do
    cd ${CASE}
    echo -e "\033[31m Starting ${CASE} \033[0m"
    ./generate_config.sh && ./run.erl && ./gc.sh
    cd -
done