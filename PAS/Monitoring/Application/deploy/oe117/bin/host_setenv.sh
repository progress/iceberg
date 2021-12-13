#!/bin/sh

# Get a non-loopback address to use for identification of this server.
PUBLIC_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1`
export PUBLIC_IP
