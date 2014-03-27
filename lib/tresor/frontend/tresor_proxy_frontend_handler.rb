module Tresor
  module Frontend
    class TresorProxyFrontendHandler < FrontendHandler
      class << self
        def can_handle?(connection)
          connection.http_parser.headers['Host'] &&
          connection.http_parser.headers['Host'].start_with?(connection.proxy.hostname)
        end

        def build_hello_message
          "Hello from TRESOR proxy."
        end
      end

      def initialize(connection)
        super(connection)
      end

      def on_body(chunk)

      end

      def on_message_complete
        connection.send_data "HTTP/1.1 200 OK\r\n"
        connection.send_data "Host: #{connection.proxy.hostname}\r\n"
        connection.send_data "Content-Length: #{build_hello_message.length}\r\n\r\n"
        connection.send_data build_hello_message

        log.debug (log_key) { 'Sent TRESOR proxy hello message.' }
      end

      def build_hello_message
        self.class.build_hello_message
      end
    end
  end
end