# TRESOR Proxy

The TRESOR distributed cloud proxy is a high-performance, modular and customizable cloud proxy, based on the [EventMachine](http://www.rubydoc.info/github/eventmachine/eventmachine) envent-driven I/O and lightweight concurrency library for Ruby. It applies event-driven I/O using the [Reactor pattern](http://en.wikipedia.org/wiki/Reactor_pattern), much like [JBoss Netty](http://www.jboss.org/netty), [Apache MINA](http://mina.apache.org/), Python's [Twisted](http://twistedmatrix.com), [Node.js](http://nodejs.org), libevent and libev. It furthermore relies on the [http_parser.rb Gem](https://github.com/tmm1/http_parser.rb), which includes a C-based parser for HTTP messages.

Its main functions are:

* Forward and Reverse proxying of HTTP traffic
* HTTP and HTTP (TLS) listeners
* Reuse of backend connections in a connection pool
* Trusted Cloud Transfer Protocol (TCTP) forward and reverse support for end-to-end encryption of HTTP traffic
* XACML PEP for RESTful authorization of HTTP requests
* Claims-based SSO, currently implemented through Microsoft Active Directory Federation Services Federation Provider
* Using the TRESOR Broker for routing of booked services

# Install and Run

The proxy can either be executed via docker, or through manually cloning the repo.

## Via Docker

There is an [automated build for the latest proxy version](https://registry.hub.docker.com/u/mathiasslawik/tresor-proxy) in the docker registry.

To run the proxy, just execute the image, specifying the applicable proxy command line options:

    docker run -i -t mathiasslawik/tresor-proxy <options>

## Manually

The proxy requires at least Ruby 2.0 (MRI). It was tested on Linux (Ubuntu 14.04 LTS) and Windows 8.1.

To install, clone the GitHub repo and use `bundle install` in the root folder.

To run the proxy, execute the following command in the cloned repo:

    bundle exec ruby bin/proxy.rb <options>

# Proxy configuration

The proxy can be configured using the command line. It will output its command line options by running `bin/proxy.rb --help`.

They are:

    Usage: proxy.rb [options]
    -b, --broker           The URL of the TRESOR broker
    -i, --ip               The ip address to bind to (default: all)
    -p, --port             The port number (default: 80)
    -n, --hostname         The HTTP hostname of the proxy (default: proxy.local)
    -P, --threadpool       The Eventmachine thread pool size (default: 20)
    -t, --trace            Enable tracing
    -l, --loglevel         Specify log level (FATAL, ERROR, WARN, INFO, DEBUG - default INFO)
        --logfile          Specify log file
    -C, --tctp_client      Enable TCTP client
    -S, --tctp_server      Enable TCTP server
        --tls              Enable TLS
        --tls_key          Path to TLS key
        --tls_crt          Path to TLS server certificate
        --reverse          Load reverse proxy settings from YAML file
        --raw_output       Output RAW data on console
        --sso              Perform claims based authentication
        --xacml            Perform XACML
        --pdpurl           The PDP URL
        --fpurl            The SSO federation provider URL
        --hrurl            The SSO home realm URL
    -h, --help             Display this help message.

The default configuration runs a forward proxy on port 80 with the HTTP hostname "proxy.local".

## IP and port

The IP and port can be specified using `-i`, and `-p` respectively.

## Trusted Cloud Transfer Protocol (TCTP) support

The proxy can act as TCTP client and server:

* ***TCTP client***: If the proxy makes backend connections, it will perform TCTP discovery with backend hosts. If a backend host supports TCTP, it will perform the TCTP handshake to create HALECs (HTTP Application-Layer Encryption Channels) and use these HALECs to encrypt relayed HTTP traffic end-to-end.
* ***TCTP server***: If the proxy is accessed by HTTP clients, it will respond to TCTP discovery requests and offer facilities to create HALECs and encrypt HTTP traffic.

## Reverse Proxying

There are two sources for the retrieval of the reverse URLs of proxied services: _reverse mappings_ and a TRESOR broker.

### Reverse mappings

Reverse mappings are contained in a YAML file, whose path is given by `--reverse <path>`.

It consists of pairs of incoming HTTP hostnames and URLs to the reverse hosts. The proxy uses the reverse URL as the HTTP `Host` header. The original HTTP hostname is retained in an additional `X-Forwarded-Host` header.

This is an example reverse mapping file:

    ---
    'www.my-service.com': 'http://my-service.local'
    'www.another-service.com': 'http://my-other-service.local'

It would instruct to redirect all requests with `Host: www.my-service.com` to the server `http://my-service.local`. The backend server would receive the headers `Host: my-service.local` and `X-Forwarded-Host: www.my-service.com`.

### Reverse proxying by using the TRESOR broker

If specifying the URL to a TRESOR broker using `-b <TRESOR broker URL>`, the TRESOR broker would be queried for the endpoint of a booked service of the current TRESOR client, which would have the same symbolic name as the part of the hostname preceding the first dot. For example: if the Proxy is queried for `servicea.service.cloud-tresor.de` it would query the broker for `servicea`.

## TLS functionality

To enable TLS secured traffic, specify the `--tls` command line option.

### TLS Server certificate

The path to the TLS server certificate can be specified through the `--tls_crt` command line option. The certificate has to be a readable file that contants a chain of X509 certificates in the [PEM format](http://en.wikipedia.org/wiki/Privacy-enhanced_Electronic_Mail), with the most-resolved certificate at the top of the file, successive intermediate certs in the middle, and the root (or CA) cert at the bottom.

### TLS Server certificate keyfile

The path to the TLS server certificate keyfile is specified through the `--tls_key` command line option. The key file path has to point to a readable file that must contain a private key in the [PEM format](http://en.wikipedia.org/wiki/Privacy-enhanced_Electronic_Mail).

## Single sign-on

The proxy can authenticate users by redirecting them to a Federation Provider and processing the resulting SAML tokens. This functionality needs the options `--fpurl <URL>` for specifying the URL of the federation provider, `--hrurl <URL>` for specifying the home realm URL, and `-n <hostname>` for specifying the hostname to be used for processing SAML tokens.