require 'eventmachine'

module Tresor
  ##
  # The connection to the TRESOR service.
  class Backend < EventMachine::Connection
    attr_accessor :plexer
    attr_accessor :host
    attr :http_parser

    def initialize
      @connection_future = EM::DefaultDeferrable.new
      @http_parser = HTTP::Parser.new

      @http_parser.on_message_complete = proc do |env|
        Tresor::ConnectionPool.backend_free(host, self)
      end
    end

    ##
    # Execute callbacks of the connection future, as soon as the connection to the TRESOR service is completed.
    def connection_completed
      @connection_future.succeed
    end

    ##
    # Send all received data to the HTTP parser
    def receive_data(data)
      @plexer.relay_from_backend data

      EM.defer do
        @http_parser << data
      end
    end

    # Buffer data until the connection to the backend server
    # is established and is ready for use
    def send_upstream(data)
      @connection_future.callback { send_data data }
    end

    ##
    # Notify the connection pool, that this backend connection was unbound.
    def unbind
      EM.defer do
        Tresor::ConnectionPool.backend_unbind(host, self)
      end
    end
  end
end