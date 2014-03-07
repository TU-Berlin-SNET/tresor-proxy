module Tresor
  module Frontend
    class TCTPDiscoveryFrontendHandler < FrontendHandler
      DISCOVERY_INFORMATION = '/.*:/halecs'
      DISCOVERY_MEDIA_TYPE = 'text/prs.tctp-discovery'

      class << self
        def can_handle?(connection)
          connection.proxy.is_tctp_server &&
          connection.http_parser.http_method.eql?('OPTIONS') &&
          connection.http_parser.headers['Accept'].eql?(DISCOVERY_MEDIA_TYPE)
        end

        def discovery_response
          @discovery_response ||= "HTTP/1.1 200 OK\r\nContent-Type: #{DISCOVERY_MEDIA_TYPE}\r\nContent-Length: #{DISCOVERY_INFORMATION.length}\r\n\r\n#{DISCOVERY_INFORMATION}"
        end
      end

      # @param [EventMachine::Connection] connection
      def initialize(connection)
        super(connection)

        log.debug (log_key) {'Got TCTP discovery request'}

        connection.send_data TCTPDiscoveryFrontendHandler.discovery_response
      end

      def on_message_complete

      end
    end
  end
end