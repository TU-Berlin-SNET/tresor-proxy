require 'active_support'
require 'eventmachine'
require 'http_parser'

##
#
# Author::  Mathias Slawik (mailto:mathias.slawik@tu-berlin.de)
# License:: Apache License 2.0
module Tresor
  extend ActiveSupport::Autoload

  autoload :Backend
  autoload :Frontend
  autoload :TCTP
  autoload :Proxy

  ActiveSupport::Dependencies::Loadable.require_dependency File.join(__dir__, 'tresor', 'logging.rb')
end