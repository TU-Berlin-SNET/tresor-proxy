module Tresor
  # TODO Refactor chunking to #chunk utility method
  module Proxy
    extend ActiveSupport::Autoload

    autoload :TresorProxy
    autoload :Connection
    autoload :ConnectionPool
  end
end