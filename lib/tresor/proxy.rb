module Tresor
  # TODO Refactor chunking to #chunk utility method
  module Proxy
    extend ActiveSupport::Autoload

    autoload :Request
    autoload :TresorProxy
    autoload :Connection
    autoload :ConnectionPool
  end
end