REBAR = ./rebar -j8

.PHONY: all deps test clean

all: deps compile

deps:
	${REBAR} get-deps

compile: deps
	${REBAR} compile

generate: compile
	cd rel && ../${REBAR} generate -f

console: generate
	./rel/redis_proxy/bin/redis_proxy console

clean:
	${REBAR} clean

test:
	cd test && ./generate_config.sh && ./run.erl && ./gc.sh