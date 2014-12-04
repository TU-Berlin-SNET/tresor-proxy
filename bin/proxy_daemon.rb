# this is myserver_control.rb
require 'daemons'

Daemons.run(File.join(File.dirname(File.realpath(__FILE__)), 'proxy.rb'))