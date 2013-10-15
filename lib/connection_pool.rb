require_relative 'backend'

require 'eventmachine'

module Tresor
  module ConnectionPool
    @free_host_connections = {}

    def self.get_backend_future_for_host(host, client_connection)
      backend_future = EventMachine::DefaultDeferrable.new

      EM.defer do
        @free_host_connections[host] ||= []

        host_connection = @free_host_connections[host].pop
        if host_connection == nil
          host_connection = EventMachine::connect('217.79.181.30', '3001', Tresor::Backend) do |c|
            c.host = host
          end
        end
        host_connection.plexer = client_connection

        backend_future.succeed host_connection
      end

      backend_future
    end

    def self.backend_free(host, backend)
      @free_host_connections[host] << backend
    end

    def self.backend_unbind(host, backend)
      @free_host_connections[host].delete(backend)
    end
  end
end