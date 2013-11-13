module Tresor
  module Backend
    class BackendHandler
      attr :backend

      def build_start_line
        "#{@backend.client_method} #{@backend.client_path}#{@backend.client_query_string ? "?#{@backend.client_query_string}": ''} HTTP/1.1\r\n"
      end
    end
  end
end