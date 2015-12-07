REBAR = ./rebar -j8

.PHONY: deps

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