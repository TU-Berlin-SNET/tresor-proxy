#!/bin/sh
while true; do
	bundle exec ruby bin/proxy.rb -a -l DEBUG -sso -p 80 -fpurl https://tresor-dev-fp.snet.tu-berlin.de -hrurl http://tresor.snet.tu-berlin.de/trust -pdpurl http://xacml.snet.tu-berlin.de:9090/pdp -y reverse.yml -f proxy.log
done
