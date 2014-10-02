module Tresor
  module Frontend
    class HTTPEncryptingRelayFrontendHandler < HTTPRelayFrontendHandler
      class << self
        def can_handle?(connection)
          connection.proxy.is_tctp_server && (
                connection.http_parser.headers['Accept-Encoding'].eql?('encrypted') ||
                connection.http_parser.headers['Content-Encoding'].eql?('encrypted')
          )
        end
      end

      # The Server HALEC used for encryption
      # @return [Rack::TCTP::ServerHALEC]
      # @!attr [r] server_halec
      attr :server_halec

      def initialize(connection)
        super(connection)

        connection.http_parser.headers.delete('Content-Encoding')
        connection.http_parser.headers.delete('Accept-Encoding')

        connection.http_parser.headers['Transfer-Encoding'] = 'chunked' if (connection.http_parser.headers['Content-Length'] || connection.http_parser.headers['Transfer-Encoding'])
      end

      alias :super_on_body :on_body

      def on_body(chunk)
        # Get the server HALEC url from the incoming client connection and set @server_halec to decide
        # when relaying, to either use the same HALEC (in case of HTTP bodies), or any HALEC (in case of body-
        # less HTTP requests)
        unless server_halec
          first_newline_index = chunk.index("\r\n")
          body_halec_url = chunk[0, first_newline_index]

          log.debug (log_key) { "Body was encrypted using HALEC #{body_halec_url}" }

          @server_halec = connection.proxy.halec_registry.halecs(:server)[URI(body_halec_url)]

          chunk_without_url = chunk[(first_newline_index + 2)..-1]

          unless chunk_without_url.eql? ''
            send_decrypted_data chunk_without_url
          end
        else
          send_decrypted_data chunk
        end
      end

      def on_message_complete
        if @has_request_body
          log.debug (log_key) { 'Sent encrypted backend response to client.' }

          backend.client_chunk "0\r\n\r\n" if connection.http_parser.headers['Transfer-Encoding'].eql? 'chunked'

          connection.proxy.halec_registry.halecs(:server)[@server_halec.url] = @server_halec

          @server_halec = nil
        end
      end

      # Decrypts +chunk+ and sends it to the client
      def send_decrypted_data(chunk)
        server_halec.queue.push proc {
          send_as_chunked server_halec.decrypt_data(chunk)
        }
      end

      def send_as_chunked(decrypted_data)
        unless decrypted_data.length == 0
          chunk_length_as_hex = decrypted_data.length.to_s(16)

          log.debug (log_key) { "Sending #{decrypted_data.length} (#{chunk_length_as_hex}) bytes of decrypted data from client to backend" }

          super_on_body "#{chunk_length_as_hex}\r\n#{decrypted_data}\r\n"
        end
      end

      # Encrypts +chunk+ and sends it to the client
      def relay_and_encrypt(chunk)
        server_halec.queue.push proc {
          encrypted_data = server_halec.encrypt_data(chunk)

          chunk_length_as_hex = encrypted_data.length.to_s(16)

          log.debug (log_key) { "Sending #{encrypted_data.length} (#{chunk_length_as_hex}) bytes of encrypted data from backend to client" }

          connection.send_data "#{chunk_length_as_hex}\r\n#{encrypted_data}\r\n"
        }
      end

      def relay_from_backend(data)
        # Use either the same HALEC used for sending an HTTP body, or any free HALEC
        @server_halec ||= connection.proxy.halec_registry.halecs(:server).shift[1]

        # Need to parse backend response to filter out headers
        unless @client_http_parser
          @client_http_parser = HTTP::Parser.new

          # Relay all headers as is, except for Transfer-Encoding, Content-Encoding. Send HALEC URL as first line of
          # response.
          @client_http_parser.on_headers_complete = proc do |headers|
            connection.send_data "HTTP/1.1 #{@client_http_parser.status_code}\r\n"

            headers.each do |header, value|
              if header.eql?('Transfer-Encoding') || header.eql?('Content-Length')
                @has_body = true

                next
              end

              connection.send_data "#{header}: #{value}\r\n"
            end

            if @has_body
              connection.send_data "Transfer-Encoding: chunked\r\n"
              connection.send_data "Content-Encoding: encrypted\r\n\r\n"

              server_halec_url_plus_line_break_length_as_hex = (@server_halec.url.to_s.length + 2).to_s(16)

              connection.send_data "#{server_halec_url_plus_line_break_length_as_hex}\r\n#{@server_halec.url}\r\n"
            end

            connection.send_data "\r\n"
          end

          # Encrypt each part of backend body
          @client_http_parser.on_body = proc do |chunk|
            relay_and_encrypt chunk
          end

          # If the backend response is complete, return the HALEC
          @client_http_parser.on_message_complete = proc do
            server_halec.queue.push proc {
              connection.send_data "0\r\n\r\n"

              connection.proxy.halec_registry.register_halec(:server, @server_halec)
            }
          end
        end

        log.debug (log_key) {"Sending #{data.size} bytes to HTTP parser to be encrypted to client."}

        @client_http_parser << data
      end
    end
  end
end