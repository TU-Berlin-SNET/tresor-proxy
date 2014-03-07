require 'uri'
require 'resolv'

module Tresor::Proxy
  class ConnectionPool
    attr_reader :free_backends
    attr_reader :proxy

    def initialize(proxy)
      @proxy = proxy
      @free_backends = {}
    end

    def get_backend_future(connection, &block)
      # Forward proxy
      if connection.http_parser.request_url.start_with?('http')
        get_backend_future_for_forward_url(connection, &block)
      else
        get_backend_future_for_reverse_host(connection, &block)
      end
    end

    def get_backend_future_for_forward_url(connection, host = nil, port = nil, &block)
      uri = URI.parse(connection.http_parser.request_url)

      get_backend_future_for_host(uri.hostname, uri.port, uri.host, connection, &block)
    end

    def get_backend_future_for_reverse_host(connection, &block)
      requested_host = connection.http_parser.headers['Host'].partition(':').first

      reverse_host = @proxy.reverse_mappings[requested_host]

      if reverse_host
        parsed_reverse_host = URI(reverse_host)

        get_backend_future_for_host(parsed_reverse_host.hostname, parsed_reverse_host.port, requested_host, connection, &block)
      else
        backend_future = EventMachine::DefaultDeferrable.new
        backend_future.fail "This proxy is not configured to reverse proxy #{requested_host}"
        backend_future
      end
    end

    def get_backend_future_for_host(host, port, http_hostname, client_connection, &block)
      backend_future = EventMachine::DefaultDeferrable.new

      EM.defer do
        begin
          ip = resolve_host(host)

          connection_key = "#{ip}:#{port}"

          @free_backends[connection_key] ||= []

          backend = @free_backends[connection_key].pop
          if backend.nil?
            backend = EventMachine::connect(ip, port, Tresor::Backend::BasicBackend) do |b|
              b.connection_pool_key = connection_key
              b.host = http_hostname
              b.proxy = client_connection.proxy
            end
            log.debug (log_key) { "Created connection #{backend.__id__} to #{connection_key} (Host: #{http_hostname})" }
          else
            log.debug (log_key) { "Reusing connection #{backend.__id__} to #{connection_key} (Host: #{http_hostname})" }
          end
          backend.plexer = client_connection

          block.call backend

          EM.schedule do
            backend_future.succeed backend
          end
        rescue SocketError => e
          EM.schedule do
            backend_future.fail e
          end
        end
      end

      backend_future
    end

    def resolve_host(hostname)
      ipInt = Socket.gethostbyname(hostname)[3]

      return "%d.%d.%d.%d" % [ipInt[0].ord, ipInt[1].ord, ipInt[2].ord, ipInt[3].ord]
    end

    def backend_free(connection_pool_key, backend)
      @free_backends[connection_pool_key] << backend
    end

    def backend_unbind(connection_pool_key, backend)
      @free_backends[connection_pool_key].delete(backend)
    end

    def log_key
      "#{@proxy.name} - Connection pool - Thread #{Thread.current.__id__}"
    end
  end
end