module Tresor
  module Frontend
    class TCTPHandshakeFrontendHandler < FrontendHandler
      class << self
        def can_handle?(connection)
          connection.proxy.is_tctp_server &&
          connection.http_parser.http_method.eql?('POST') &&
          connection.http_parser.request_url.start_with?('/halecs/')
        end
      end

      def initialize(connection)
        super(connection)

        # Get HALEC URL
        halec_url = URI("http://#{connection.proxy.hostname}:#{connection.proxy.port}#{connection.http_parser.request_url}")

        # TCTP handshake
        @server_halec = connection.proxy.halec_registry.halecs(:server)[halec_url]

        @handshake_data = []
      end

      def on_body(chunk)
        @handshake_data << chunk
      end

      def on_message_complete
        EM.defer do
          @server_halec.engine.inject @handshake_data.join

          @server_halec.engine.read

          handshake_response = @server_halec.engine.extract
          connection.send_data "HTTP/1.1 200 OK\r\nContent-Length: #{handshake_response.length}\r\n\r\n#{handshake_response}"
        end
      end
    end
  end
end