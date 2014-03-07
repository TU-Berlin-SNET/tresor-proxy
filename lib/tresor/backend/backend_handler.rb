module Tresor
  module Backend
    # A BackendHandler
    class BackendHandler
      # The Backend
      # @return [Tresor::Backend::BasicBackend] The backend
      attr :backend

      def build_start_line
        "#{@backend.client_method} #{@backend.client_path}#{@backend.client_query_string ? "?#{@backend.client_query_string}": ''} HTTP/1.1\r\n"
      end

      # Relays data from backend to client
      def relay(data)
        backend.client_connection.frontend_handler.relay_from_backend data
      end
    end
  end
end