#!/bin/bash

if [ -d "deps/rabbit_common" ]; then
	echo "Generate rebar.config for rabbit_common, amqp_client"
	make -C deps/rabbit_common
	make -C deps/rabbit_common rebar.config	&& make -C deps/amqp_client rebar.config
fi
