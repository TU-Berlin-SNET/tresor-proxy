# TRESOR Proxy

## Overview and functionality

The TRESOR distributed cloud proxy is a modular and customizable cloud proxy.

Its main functions are:

* Trusted Cloud Transfer Protocol (TCTP) support for end-to-end encryption of HTTP traffic
* XACML PEP for RESTful authorization of HTTP request
* Claims-based SSO

## Installation

The proxy requires at least Ruby 2.0 (MRI). It was tested on Linux (Ubuntu 12.04 LTS) and Windows 8.1.

To install, clone the GitHub repo and run `bundle install`.

## Command line options

The proxy will output its command line options by running `bin/proxy.rb --help`.

They are:

