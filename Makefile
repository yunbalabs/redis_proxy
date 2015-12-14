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

test:
	cd test && ./generate_config.sh && ./run.erl && ./gc.sh