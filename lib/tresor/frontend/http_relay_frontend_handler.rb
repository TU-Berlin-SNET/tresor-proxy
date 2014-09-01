module Tresor
  module Frontend
    class HTTPRelayFrontendHandler < FrontendHandler
      class << self
        def can_handle?(connection)
          # TODO Test for configured reverse / forward functionality
          true
        end
      end

      attr_accessor :backend

      # Initializes this HTTP relay handler by getting a backend future
      # @param [EventMachine::Connection] connection The client connection
      def initialize(connection)
        super(connection)

        @has_request_body = false

        if connection.proxy.is_sso_enabled
          sso_id = connection.query_vars['tresor_sso_id']

          if sso_id
            connection.additional_headers_to_relay['Set-Cookie'] = "tresor_sso_id=#{sso_id}; path=/"
          end
        end

        @backend = Tresor::Backend::Backend.new(connection)
      end

      # Sends any client chunk directly to backend.
      def on_body(chunk)
        @has_request_body = true

        backend.client_chunk chunk
      end

      def on_message_complete
        backend.client_chunk :last
      end

      # Called from backend
      def relay_from_backend(data)
        log.debug (log_key) {"Received #{data.size} bytes from backend."}

        log.debug (log_key) {"Relaying #{data.size} bytes directly to client."}

        connection.send_data data
      end

      def send_client_trailer_chunk
        backend.client_chunk "0\r\n\r\n"
      end
    end
  end
end