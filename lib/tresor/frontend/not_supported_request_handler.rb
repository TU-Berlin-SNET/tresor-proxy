module Tresor
  module Frontend
    class NotSupportedRequestHandler < FrontendHandler
      class << self
        def can_handle?(connection)
          connection.request.http_method.eql?('CONNECT')
        end
      end

      # @param [EventMachine::Connection] connection
      def initialize(connection)
        super(connection)

        log.debug (log_key) {'Got unsupported request'}
      end

      def on_body(chunk)

      end

      def on_message_complete
        if connection.request.http_method.eql?('CONNECT')
          connection.send_data "HTTP/1.1 405 Method Not Allowed\r\n"
          connection.send_data "Allow: GET, HEAD, POST, PUT, DELETE, TRACE\r\n"
          connection.send_data "Content-Length: 0\r\n"
          connection.send_data "\r\n"
        end
      end
    end
  end
end
