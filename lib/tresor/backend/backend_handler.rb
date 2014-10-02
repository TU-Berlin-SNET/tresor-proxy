module Tresor
  module Backend
    # A BackendHandler
    class BackendHandler
      # The Backend
      # @return [Tresor::Backend::Backend] The backend
      attr :backend

      # A future connected backend
      attr :backend_connection_future

      # The currently connected backend connection
      # @return [Tresor::Backend::BackendConnection]
      attr :backend_connection

      # @param [Tresor::Backend::Backend] backend
      def initialize(backend)
        @backend = backend

        @backend_connection_future = backend.proxy.connection_pool.get_backend_future(backend.client_connection, self)
        @backend_connection_future.callback do |backend_connection|
          @backend_connection = backend_connection
        end

        @backend_connection_future.errback do |error|
          backend.client_connection.send_error_response(Exception.new(error))
          backend.client_connection.close_connection_after_writing
        end
      end

      def build_start_line
        request = backend.client_connection.request

        "#{request.http_method} #{request.requested_http_request_url} HTTP/1.1\r\n"
      end

      def on_backend_headers_complete
        throw Exception("Unimplemented #{self.class.name}#on_backend_headers_complete")
      end

      def on_backend_body(chunk)
        throw Exception("Unimplemented #{self.class.name}#on_backend_body")
      end

      def on_backend_message_complete
        throw Exception("Unimplemented #{self.class.name}#on_backend_message_complete")
      end

      def on_client_message_complete
        throw Exception("Unimplemented #{self.class.name}#on_client_message_complete")
      end

      # Relays data from backend to client
      def relay(data)
        backend.client_connection.frontend_handler_future.callback do |frontend_handler|
          frontend_handler.relay_from_backend data
        end
      end
    end
  end
end