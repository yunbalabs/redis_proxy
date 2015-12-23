REBAR = ./rebar -j8

.PHONY: all deps test clean

all: deps compile

deps:
	${REBAR} get-deps

compile: deps
	${REBAR} compile

generate: compile
	cd rel && ../${REBAR} generate -f

start: generate
	./rel/redis_proxy/bin/redis_proxy start

stop:
	./rel/redis_proxy/bin/redis_proxy stop

clean:
	${REBAR} clean

test: compile
	cd test && ./run.sh