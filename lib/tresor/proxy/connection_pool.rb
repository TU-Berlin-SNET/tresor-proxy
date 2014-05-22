require 'uri'
require 'resolv'

module Tresor::Proxy
  class ConnectionPool
    attr_reader :free_backends
    attr_reader :proxy
    attr_reader :pool_mutex

    def initialize(proxy)
      @proxy = proxy
      @free_backends = {}
      @pool_mutex = Mutex.new
    end

    # @param [Tresor::Proxy::Connection] connection
    # @param [Tresor::Backend::BackendHandler] handler
    def get_backend_future(connection, handler)
      # Forward proxy
      if connection.http_parser.request_url.start_with?('http')
        get_backend_future_for_forward_url(connection, handler)
      else
        get_backend_future_for_reverse_host(connection, handler)
      end
    end

    # @param [Tresor::Proxy::Connection] connection
    def get_backend_future_for_forward_url(connection, handler, host = nil, port = nil)
      uri = connection.parsed_request_uri

      get_backend_future_for_host(uri.hostname, uri.port, uri.host, connection, handler)
    end

    # @param [Tresor::Proxy::Connection] connection
    def get_backend_future_for_reverse_host(connection, handler)
      requested_host = connection.host.partition(':').first

      reverse_host = @proxy.reverse_mappings[requested_host]

      if reverse_host
        parsed_reverse_host = URI(reverse_host)

        get_backend_future_for_host(parsed_reverse_host.hostname, parsed_reverse_host.port, requested_host, connection, handler)
      else
        backend_future = EventMachine::DefaultDeferrable.new
        backend_future.fail "This proxy is not configured to reverse proxy #{requested_host}"
        backend_future
      end
    end

    # @param [Tresor::Proxy::Connection] client_connection
    def get_backend_future_for_host(host, port, http_hostname, client_connection, handler)
      backend_future = EventMachine::DefaultDeferrable.new

      EM.defer do
        begin
          ip = resolve_host(host)

          connection_key = "#{ip}:#{port}"

          backend = nil

          @pool_mutex.synchronize do
            @free_backends[connection_key] ||= []

            backend = @free_backends[connection_key].pop
          end

          if backend.nil?
            backend = EventMachine::connect(ip, port, Tresor::Backend::BackendConnection, proxy, connection_key, handler)

            log.debug (log_key) { "Created connection #{backend.__id__} to #{connection_key} (Host: #{http_hostname})" }
          else
            backend.backend_handler = handler

            log.debug (log_key) { "Reusing connection #{backend.__id__} to #{connection_key} (Host: #{http_hostname})" }
          end

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

    def mark_as_available(connection_pool_key, backend)
      @free_backends[connection_pool_key] << backend
    end

    def backend_destroy(backend)
      @pool_mutex.synchronize do
        @free_backends[backend.connection_pool_key].delete(backend)
      end
    end

    def log_key
      "#{@proxy.name} - Connection pool - Thread #{Thread.current.__id__}"
    end
  end
end