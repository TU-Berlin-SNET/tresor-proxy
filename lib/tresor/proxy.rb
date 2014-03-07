module Tresor
  module Proxy
    extend ActiveSupport::Autoload

    autoload :Connection
    autoload :TresorProxy
    autoload :ConnectionPool
  end
end