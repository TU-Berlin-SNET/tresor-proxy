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
      backend_future = EventMachine::DefaultDeferrable.new

      EM.defer do
        request = connection.request

        if request.http_relay?
          begin
            ip = resolve_host(request.effective_backend_url.host)
            port = request.effective_backend_url.port

            connection_key = "#{ip}:#{port}"

            backend = nil

            @pool_mutex.synchronize do
              @free_backends[connection_key] ||= []

              backend = @free_backends[connection_key].pop
            end

            if backend.nil?
              backend = EventMachine::connect(ip, port, Tresor::Backend::BackendConnection, proxy, connection_key, handler)

              log.debug (log_key) { "Created connection #{backend.__id__} to #{connection_key} (Host: #{request.effective_backend_url.host})" }
            else
              backend.backend_handler = handler

              log.debug (log_key) { "Reusing connection #{backend.__id__} to #{connection_key} (Host: #{request.effective_backend_url.host})" }
            end

            EM.schedule do
              backend_future.succeed backend
            end
          rescue SocketError => e
            EM.schedule do
              backend_future.fail e
            end
          end
        else
          backend_future.fail Exception.new("HTTP request cannot be relayed.")
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