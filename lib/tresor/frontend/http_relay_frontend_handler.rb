module Tresor
  module Frontend
    class HTTPRelayFrontendHandler < FrontendHandler
      class << self
        def can_handle?(connection)
          # TODO Test for configured reverse / forward functionality
          true
        end
      end

      attr_accessor :backend_future

      # Initializes this HTTP relay handler by getting a backend future and notifying it with the client
      # request.
      # @param [EventMachine::Connection] connection The client connection
      def initialize(connection)
        super(connection)

        # TODO Untangle #relay_from_backend from Connection
        connection.define_singleton_method(:relay_from_backend) do |data|
          frontend_handler.relay_from_backend data
        end

        @backend_future = connection.proxy.connection_pool.get_backend_future(connection)

        @backend_future.callback do |backend|
          parsed_uri = URI.parse(connection.http_parser.request_url)

          parsed_uri.path = '/' if parsed_uri.path.eql?('')

          backend.client_request connection.http_parser.http_method, parsed_uri.path, parsed_uri.query, connection.http_parser.headers
        end

        @backend_future.errback do |error|
          send_error_response(error)

          close_connection_after_writing
        end

        @has_request_body = false
      end

      # Sends any client chunk directly to backend.
      def on_body(chunk)
        @has_request_body = true

        @backend_future.callback do |backend|
          backend.client_chunk chunk
        end
      end

      def on_message_complete
        if @has_request_body
          @backend_future.callback do |backend|
            send_client_trailer_chunk if connection.http_parser.headers['Transfer-Encoding'].eql?('chunked') || backend.backend_handler.is_a?(Tresor::Backend::TCTPEncryptToBackendHandler)
          end
        end
      end

      # Called from backend
      def relay_from_backend(data)
        log.debug (log_key) {"Received #{data.size} bytes from backend."}

        log.debug (log_key) {"Relaying #{data.size} bytes directly to client."}
        connection.send_data data

        unless @client_http_parser
          @client_http_parser = HTTP::Parser.new

          @client_http_parser.on_message_complete = proc do
            connection.reset_http_parser
          end
        end
      end

      def send_client_trailer_chunk
        @backend_future.callback do |backend|
          backend.client_chunk "0\r\n\r\n"
        end
      end
    end
  end
end