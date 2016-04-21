.PHONY: all clean compile deps distclean release
REBAR := $(shell which ./rebar || which rebar)

all: deps compile

compile: deps
	./amqp.sh
	$(REBAR) compile

deps:
	$(REBAR) get-deps

clean:
	$(REBAR) clean
	rm -rf ./ebin
	rm -rf ./logs
	rm -f ./erl_crash.dump
	rm -rf ./.eunit
	rm -f ./test/*.beam
	rm -rf ./rel/bs_selector

distclean: clean
	$(REBAR) delete-deps

release: compile
	cd rel && ../rebar generate && tar -cjf xkeam.tar.bz2 xkeam

DIALYZER_APPS = kernel stdlib sasl erts eunit ssl tools crypto \
       inets public_key syntax_tools compiler

include tools.mk
