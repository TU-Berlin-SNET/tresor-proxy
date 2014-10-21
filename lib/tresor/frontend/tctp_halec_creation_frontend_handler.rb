module Tresor
  module Frontend
    class TCTPHalecCreationFrontendHandler < FrontendHandler
      class << self
        def can_handle?(connection)
          connection.proxy.is_tctp_server &&
          connection.request.http_method.eql?('POST') &&
          connection.request.requested_http_request_url.eql?('/halecs')
        end
      end

      def initialize(connection)
        super(connection)

        @server_halec = Rack::TCTP::ServerHALEC.new
        @server_halec.queue = EventMachine::Queue.new
        @handshake_data = []
      end

      def on_body(chunk)
        @handshake_data << chunk
      end

      def on_message_complete
        @server_halec.engine.inject @handshake_data.join

        halec_url = connection.request.effective_request_url.dup
        halec_url.query = nil
        halec_url.path = "/halecs/#{Rack::TCTP::ServerHALEC.new_slug}"

        @server_halec.engine.read
        handshake_response = @server_halec.engine.extract

        @server_halec.url = halec_url

        connection.proxy.halec_registry.register_halec(:server, @server_halec)

        log.debug(log_key) {"Registered server HALEC #{@server_halec.url}"}

        connection.send_data "HTTP/1.1 200 OK\r\nLocation: #{halec_url.to_s}\r\nContent-Length: #{handshake_response.length}\r\n\r\n#{handshake_response}"
      end
    end
  end
end