require_relative 'backend/basic_backend'

require 'eventmachine'
require 'uri'
require 'resolv'

module Tresor
  module ConnectionPool
    @free_backends = {}

    def self.get_backend_future_for_forward_url(url, client_connection)
      uri = URI.parse(url)

      ipInt = Socket.gethostbyname(uri.host)[3]
      ip =  "%d.%d.%d.%d" % [ipInt[0].ord, ipInt[1].ord, ipInt[2].ord, ipInt[3].ord]

      get_backend_future_for_host(ip, uri.port, uri.host, client_connection)
    end

    def self.get_backend_future_for_reverse_host(host, client_connection)
      #self.get_backend_future_for_host()
    end

    def self.get_backend_future_for_host(ip, port, host, client_connection)
      backend_future = EventMachine::DefaultDeferrable.new

      connection_key = "#{ip}:#{port}"

      EM.defer do
        @free_backends[connection_key] ||= []

        backend = @free_backends[connection_key].pop
        if backend == nil
          backend = EventMachine::connect(ip, port, Tresor::Backend::BasicBackend) do |b|
            b.connection_pool_key = connection_key
            b.host = host
            b.proxy = client_connection.proxy
          end
          log.debug ('ConnectionPool') { "Created connection #{backend.__id__} to #{connection_key} (Host: #{host})" }
        else
          log.debug ('ConnectionPool') { "Reusing connection #{backend.__id__} to #{connection_key} (Host: #{host})" }
        end
        backend.plexer = client_connection

        backend_future.succeed backend
      end

      backend_future
    end

    def self.backend_free(connection_pool_key, backend)
      @free_backends[connection_pool_key] << backend
    end

    def self.backend_unbind(connection_pool_key, backend)
      @free_backends[connection_pool_key].delete(backend)
    end
  end
end