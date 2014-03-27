module Tresor
  module Backend
    class RelayingBackendHandler < BackendHandler
      def initialize(backend)
        @backend = backend

        @http_parser = HTTP::Parser.new

        @http_parser.on_headers_complete = proc do |headers|
          on_backend_headers_complete headers
        end

        @http_parser.on_body = proc do |chunk|
          on_backend_body chunk
        end

        @http_parser.on_message_complete = proc do |env|
          on_backend_message_complete
        end

        send_request_to_backend

        EM.schedule do
          @backend.client_chunk_future.succeed self
          @backend.receive_data_future.succeed self
        end
      end

      def receive_data(data)
        @http_parser << data
      end

      def send_request_to_backend
        start_line = build_start_line

        log.debug (log_key) { "Relaying to backend: #{start_line}" }

        backend.send_data start_line
        send_client_headers(backend.client_headers)

        #if(@backend.client_connection.query_vars['tresor_sso_id'])
        #  sso_id = @backend.client_connection.query_vars['tresor_sso_id']
        #
        #  sso_token = Tresor::Frontend::ClaimSSO::RedirectToSSOFrontendHandler.sso_sessions[sso_id]
        #
        #  backend.send_data "TRESOR-Identity: #{sso_token.name_id}\r\n"
        #end

        backend.send_data "\r\n"
      end

      def client_chunk(chunk)
        backend.send_data chunk
      end

      def send_client_headers(headers)
        case headers
          when Hash
            headers.each do |header, value|
              backend.send_data "#{header}: #{value}\r\n"
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

      def on_backend_headers_complete(headers)
        relay "HTTP/1.1 #{@http_parser.status_code}\r\n"

        # Thats better
        headers.delete('Content-Length') if headers['Transfer-Encoding']

        if(headers['Connection'])
          puts headers['Connection']
        end

        relay_backend_headers headers

        relay "\r\n"
      end

      def on_backend_body(chunk)
        if @http_parser.headers['Transfer-Encoding'] && @http_parser.headers['Transfer-Encoding'].eql?('chunked')
          relay_as_chunked chunk
        else
          relay chunk
        end
      end

      def on_backend_message_complete
        relay "0\r\n\r\n" if @http_parser.headers['Transfer-Encoding'] && @http_parser.headers['Transfer-Encoding'].eql?('chunked')

        @backend.free_backend
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