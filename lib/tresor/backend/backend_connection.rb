module Tresor
  module Backend
    # HTTP connection to backend. Does callbacks to #backend_handler.
    class BackendConnection < EventMachine::Connection
      # The key onto which this backend is registered with the proxy connection pool
      # @return [String]
      # @!attr [rw] connection_pool_key
      attr :connection_pool_key

      # The HTTP parser used for parsing the request
      # @!attr [r] http_parser
      # @return [HTTP::Parser]
      attr :http_parser

      # The TRESOR proxy, which owns this backend
      # @!attr [r] proxy
      # @return [Tresor::Proxy::TresorProxy]
      attr :proxy

      # The backend handler, which handles responses from this backend
      # @!attr [rw] backend_handler
      # @return [Tresor::Backend::BackendHandler]
      attr_accessor :backend_handler

      # @param [Tresor::Proxy::TresorProxy] proxy
      # @param [String] connection_pool_key
      def initialize(proxy, connection_pool_key, backend_handler)
        @proxy = proxy
        @connection_pool_key = connection_pool_key
        @backend_handler = backend_handler

        @http_parser = HTTP::Parser.new

        http_parser.on_headers_complete = proc do |headers|
          on_backend_headers_complete headers
        end

        http_parser.on_body = proc do |chunk|
          on_backend_body chunk
        end

        http_parser.on_message_complete = proc do |env|
          on_backend_message_complete
        end
      end

      def on_backend_headers_complete(headers)
        if @backend_handler
          @backend_handler.on_backend_headers_complete headers
        else
          log (log_key) { 'Unhandled BackendConnection#on_backend_headers_complete !' }
        end
      end

      def on_backend_body(chunk)
        if @backend_handler
          @backend_handler.on_backend_body chunk
        else
          log (log_key) { 'Unhandled BackendConnection#on_backend_body !' }
        end
      end

      def on_backend_message_complete
        if @backend_handler
          @backend_handler.on_backend_message_complete

          if(@http_parser.headers['Connection'] && @http_parser.headers['Connection'].eql?('close'))
            unbind
          else
            proxy.connection_pool.mark_as_available(@connection_pool_key, self)
          end
        else
          log (log_key) { 'Unhandled BackendConnection#on_backend_message_complete !' }
        end
      end

      def send_data(data)
        # puts data

        super(data)
      end

      def receive_data(data)
        log.debug (log_key) { "Received #{data.size} bytes from backend" }

        @http_parser << data
      end

      def unbind
        if @backend_handler && @backend_handler.respond_to?(:on_unbind)
          @backend_handler.on_unbind
        end

        proxy.connection_pool.backend_destroy(self)
      end

      def log_key
        "Backend #{@connection_pool_key} #{@host} - Thread #{Thread.list.index(Thread.current)}"
      end
    end
  end
end
