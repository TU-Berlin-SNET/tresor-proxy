require_relative 'backend/basic_backend'

require 'eventmachine'
require 'uri'
require 'resolv'

module Tresor
  class ConnectionPool
    attr_reader :free_backends
    attr_reader :proxy

    def initialize(proxy)
      @proxy = proxy
      @free_backends = {}
    end

    def get_backend_future_for_forward_url(url, client_connection)
      uri = URI.parse(url)

      ipInt = Socket.gethostbyname(uri.host)[3]
      ip =  "%d.%d.%d.%d" % [ipInt[0].ord, ipInt[1].ord, ipInt[2].ord, ipInt[3].ord]

      get_backend_future_for_host(ip, uri.port, uri.host, client_connection)
    end

    def get_backend_future_for_reverse_host(host, client_connection)
      requested_host = host.partition(':').first

      reverse_host = @proxy.reverse_mappings[requested_host]

      if reverse_host
        get_backend_future_for_forward_url(reverse_host, client_connection)
      else
        backend_future = EventMachine::DefaultDeferrable.new
        backend_future.fail "This proxy is not configured to reverse proxy #{requested_host}"
        backend_future
      end
    end

    def get_backend_future_for_host(ip, port, host, client_connection)
      backend_future = EventMachine::DefaultDeferrable.new

      connection_key = "#{ip}:#{port}"

      EM.defer do
        @free_backends[connection_key] ||= []

        backend = @free_backends[connection_key].pop
        if backend.nil?
          backend = EventMachine::connect(ip, port, Tresor::Backend::BasicBackend) do |b|
            b.connection_pool_key = connection_key
            b.host = host
            b.proxy = client_connection.proxy
          end
          log.debug (log_key) { "Created connection #{backend.__id__} to #{connection_key} (Host: #{host})" }
        else
          log.debug (log_key) { "Reusing connection #{backend.__id__} to #{connection_key} (Host: #{host})" }
        end
        backend.plexer = client_connection

        backend_future.succeed backend
      end

      backend_future
    end

    def backend_free(connection_pool_key, backend)
      @free_backends[connection_pool_key] << backend
    end

    def backend_unbind(connection_pool_key, backend)
      @free_backends[connection_pool_key].delete(backend)
    end

    def log_key
      "#{@proxy.name} - Connection pool"
    end
  end
end