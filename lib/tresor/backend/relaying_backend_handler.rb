module Tresor
  module Backend
    class RelayingBackendHandler < BackendHandler
      #@return [Boolean] If the HTTP request has a body
      #@!attr [r] request_has_body
      attr :request_has_body

      def initialize(backend)
        super(backend)

        backend_connection_future.callback do |backend_connection|
          send_headers_to_backend_connection

          @request_has_body = false

          backend.client_chunk_future.succeed self
        end
      end

      def send_headers_to_backend_connection
        start_line = build_start_line

        log.debug (log_key) { "Relaying to backend: #{start_line}" }

        backend_connection.send_data start_line

        client_headers = [backend.client_connection.client_headers]

        if(sso_session = @backend.client_connection.sso_session)
          client_headers << {"TRESOR-Identity" => sso_session.name_id}

          sso_session.attributes_hash.each do |attribute, values|
            values.each do |value|
              client_headers << {"TRESOR-Attribute" => "#{attribute} #{value}"}
            end
          end
        end

        send_client_headers(client_headers)

        backend_connection.send_data "\r\n"
      end

      def client_chunk(chunk)
        @request_has_body = true

        log.debug (log_key) { "Sending #{chunk.length} bytes to backend." }

        backend_connection.send_data chunk
      end

      def on_client_message_complete
        if @request_has_body
          if backend.client_connection.http_parser.headers['Transfer-Encoding'].eql?('chunked')
            send_client_trailer_chunk
          end
        end
      end

      def send_client_headers(headers)
        case headers
          when Hash
            headers.each do |header, value|
              backend_connection.send_data "#{header}: #{value}\r\n"
            end
          when Array
            headers.each do |header_hash|
              send_client_headers header_hash
            end
        end
      end

      def relay_backend_headers(headers)
        case headers
          when Hash
            headers.each do |header, value|
              [value].flatten.each do |v| relay "#{header}: #{v}\r\n" end
            end
          when Array
            headers.each do |header_hash|
              relay_backend_headers header_hash
            end
        end
      end

      # Relays additional headers
      def relay_additional_headers
        @backend.client_connection.additional_headers_to_relay.each do |header, value|
          relay "#{header}: #{value}\r\n"
        end
      end

      def on_backend_headers_complete(headers)
        relay "HTTP/1.1 #{backend_connection.http_parser.status_code}\r\n"

        # Thats better
        headers.delete('Content-Length') if headers['Transfer-Encoding']

        if(headers['Connection'])
          puts headers['Connection']
        end

        relay_backend_headers headers

        relay_additional_headers

        relay "\r\n"
      end

      def client_transfer_chunked?
        backend_connection.http_parser.headers['Transfer-Encoding'] && backend_connection.http_parser.headers['Transfer-Encoding'].eql?('chunked')
      end

      def on_backend_body(chunk)
        if client_transfer_chunked?
          relay_as_chunked chunk
        else
          relay chunk
        end
      end

      def on_backend_message_complete
        relay "0\r\n\r\n" if client_transfer_chunked?
      end

      def log_key
        "#{@backend.proxy.name} - Relay Handler"
      end

      def relay_as_chunked(data)
        unless data.length == 0
          chunk_length_as_hex = data.length.to_s(16)

          log.debug (log_key) { "Relaying #{data.length} (#{chunk_length_as_hex}) bytes of data from backend to client" }

          relay "#{chunk_length_as_hex}\r\n#{data}\r\n"
        end
      end
    end
  end
end