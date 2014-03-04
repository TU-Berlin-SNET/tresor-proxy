module Tresor
  module Backend
    class BackendHandler
      attr :backend

      def build_start_line
        "#{@backend.client_method} #{@backend.client_path}#{@backend.client_query_string ? "?#{@backend.client_query_string}": ''} HTTP/1.1\r\n"
      end

      # Relays data from backend to client
      def relay(data)
        @backend.plexer.relay_from_backend data
      end
    end
  end
end