#!/bin/bash
. /usr/local/rvm/scripts/rvm

cd /root/tresor-proxy

bundle exec ruby bin/proxy.rb $@