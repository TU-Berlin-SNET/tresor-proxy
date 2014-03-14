module Tresor
  # TODO Refactor chunking to #chunk utility method
  module Proxy
    extend ActiveSupport::Autoload

    autoload :Connection
    autoload :TresorProxy
    autoload :ConnectionPool
  end
end