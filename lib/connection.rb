require 'http_parser'
require_relative 'connection_pool'
require_relative 'tctp/server_halec'
require_relative 'tctp/sequence_queue'

module Tresor
  ##
  # A connection from the user agent to the TRESOR proxy
  class Connection < EventMachine::Connection
    DISCOVERY_INFORMATION = '/.*:/halecs'
    DISCOVERY_MEDIA_TYPE = 'text/prs.tctp-discovery'

    attr :http_parser

    attr :client_ip
    attr :client_port

    attr_accessor :proxy

    attr :backend_future

    def initialize(proxy)
      @proxy = proxy

      @http_parser = HTTP::Parser.new

      # Create backend as soon as all headers are complete
      @http_parser.on_headers_complete = proc do
        log.debug (log_key) {"Headers complete. Request is #{@http_parser.http_method} #{@http_parser.request_url} HTTP/1.1"}

        # Test, if the request is for TCTP functionality
        if proxy.is_tctp_server && @http_parser.http_method.eql?('OPTIONS') && @http_parser.headers['Accept'].eql?(DISCOVERY_MEDIA_TYPE)
          log.debug (log_key) {'Got TCTP discovery request'}

          # TCTP discovery
          send_tctp_discovery_information
        elsif proxy.is_tctp_server && @http_parser.http_method.eql?('POST') && @http_parser.request_url.eql?('/halecs')
          # TCTP HALEC creation
          @server_halec = Tresor::TCTP::ServerHALEC.new

          @http_parser.on_body = proc do |chunk|
            @server_halec.socket_there.write chunk
          end

          @http_parser.on_message_complete = proc do
            halec_url = "/halecs/#{Tresor::TCTP::ServerHALEC.new_slug}"

            handshake_response = @server_halec.socket_there.readpartial(16384)
            send_data "HTTP/1.1 200 OK\r\n"
            send_data "Location: #{halec_url}\r\n"
            send_data "Content-Length: #{handshake_response.length}\r\n\r\n"
            send_data handshake_response

            @server_halec.url = halec_url

            proxy.halec_registry.register_halec(:server, @server_halec)
          end
        elsif proxy.is_tctp_server && @http_parser.http_method.eql?('POST') && @http_parser.request_url.start_with?('/halecs/')
          # TCTP handshake
          @server_halec = proxy.halec_registry.halecs(:server)[@http_parser.request_url]

          @http_parser.on_body = proc do |chunk|
            @server_halec.socket_there.write chunk

            handshake_response = @server_halec.socket_there.readpartial(16384)
            send_data "HTTP/1.1 200 OK\r\n"
            send_data "Content-Length: #{handshake_response.length}\r\n\r\n"
            send_data handshake_response
          end

          @http_parser.on_message_complete = proc do

          end
        else
          #Regular proxy functionality
          if @http_parser.request_url.start_with?('http')
            # Forward proxy
            @backend_future = proxy.connection_pool.get_backend_future_for_forward_url(@http_parser.request_url, self)
          else
            # Reverse proxy
            @backend_future = proxy.connection_pool.get_backend_future_for_reverse_host(@http_parser.headers['Host'], self)
          end

          # Strip TCTP encryption information from request as we are decrypting it
          if proxy.is_tctp_server && (@http_parser.headers['Accept-Encoding'].eql?('encrypted') || @http_parser.headers{'Content-Encoding'}.eql?('encrypted'))
            @http_parser.headers.delete('Content-Encoding')
            @http_parser.headers.delete('Accept-Encoding')

            @http_parser.headers['Transfer-Encoding'] = 'chunked' if (@http_parser.headers['Content-Length'] || @http_parser.headers['Transfer-Encoding'])

            @tctp_decryption_requested = true
          else
            @tctp_decryption_requested = false
          end

          #As soon as the backend is ready...
          @backend_future.callback do |backend|
            parsed_uri = URI.parse(@http_parser.request_url)

            # Inform Backend about the current client request
            backend.client_request @http_parser.http_method, parsed_uri.path, parsed_uri.query, @http_parser.headers
          end

          @backend_future.errback do |error|
            send_error_response(error)

            close_connection_after_writing
          end

          @has_request_body = false

          @http_parser.on_body = proc do |chunk|
            @has_request_body = true

            @backend_future.callback do |backend|
              if @tctp_decryption_requested
                # Get the server HALEC url from the incoming client connection and set @server_halec to decide
                # when relaying, to either use the same HALEC (in case of HTTP bodies), or any HALEC (in case of body-
                # less HTTP requests)
                unless @server_halec
                  first_newline_index = chunk.index("\r\n")
                  body_halec_url = chunk[0, first_newline_index]

                  log.debug (log_key) { "Body was encrypted using HALEC #{body_halec_url}" }

                  @server_halec = proxy.halec_registry.halecs(:server)[body_halec_url]
                  @server_halec_sequence_index = @server_halec.data_to_be_decrypted.sequence_index
                  @connection_decrypted_data_queue = Tresor::TCTP::SequenceQueue.new(@server_halec_sequence_index)

                  chunk_without_url = chunk[(first_newline_index + 2)..-1]

                  @server_halec.data_to_be_decrypted.push chunk_without_url, @server_halec_sequence_index
                  @server_halec_sequence_index += 1

                  send_decrypted_data
                else
                  @server_halec.data_to_be_decrypted.push chunk, @server_halec_sequence_index
                  @server_halec_sequence_index += 1

                  send_decrypted_data
                end
              else
                backend.client_chunk chunk
              end
            end
          end

          @http_parser.on_message_complete = proc do |env|
            if @has_request_body
              @backend_future.callback do |backend|
                if @tctp_decryption_requested
                  @server_halec.data_to_be_decrypted.push :eof, @server_halec_sequence_index
                  @server_halec_sequence_index += 1

                  send_decrypted_data
                else
                  send_client_trailer_chunk
                end
              end
            end
          end
        end
      end
    end

    def post_init
      @client_port, @client_ip = Socket.unpack_sockaddr_in(get_peername)

      log.debug (log_key) {"Connection initialized"}
    end

    def receive_data(data)
      log.debug (log_key) {"Received #{data.size} bytes from client."}

      @http_parser << data
    end

    def send_decrypted_data
      @server_halec.decrypt_data.callback do |decrypted_data_hash|
        decrypted_data_hash.each do |sequence_no, decrypted_data|
          @connection_decrypted_data_queue.push decrypted_data, sequence_no
        end

        @connection_decrypted_data_queue.shift_next_items.each do |sequence_no, decrypted_data|
          unless decrypted_data.eql?(:eof)
            send_as_chunked decrypted_data
          else
            send_client_trailer_chunk
          end
        end
      end
    end

    def send_encrypted_data
      @server_halec.encrypt_data.callback do |encrypted_data_hash|
        encrypted_data_hash.each do |sequence_no, encrypted_data|
          @connection_encrypted_data_queue.push encrypted_data, sequence_no
        end

        @connection_encrypted_data_queue.shift_next_items.each do |sequence_no, encrypted_data|
          unless encrypted_data.eql?(:eof)
            encrypted_data.each do |data_part|
              chunk_length_as_hex = data_part.length.to_s(16)

              log.debug (log_key) { "Sending #{data_part.length} (#{chunk_length_as_hex}) bytes of encrypted data from backend to client" }

              send_data "#{chunk_length_as_hex}\r\n#{data_part}\r\n"
            end
          else
            log.debug (log_key) { 'Sent encrypted backend response to client.' }

            send_data "0\r\n\r\n"

            proxy.halec_registry.halecs(:server)[@server_halec.url] = @server_halec

            @server_halec = nil
            @client_http_parser = nil
            @tctp_decryption_requested = nil
            @server_halec_encrypted_sequence_index = nil
            @connection_encrypted_data_queue = nil
          end
        end
      end
    end

    def send_as_chunked(decrypted_data)
      @backend_future.callback do |backend|
        chunk_length_as_hex = decrypted_data.length.to_s(16)

        log.debug (log_key) { "Sending #{decrypted_data.length} (#{chunk_length_as_hex}) bytes of decrypted data from client to backend" }

        @backend.client_chunk "#{chunk_length_as_hex}\r\n#{decrypted_data}\r\n"
      end
    end

    def send_client_trailer_chunk
      @backend_future.callback do |backend|
        @backend.client_chunk "0\r\n\r\n"
      end
    end

    def relay_from_backend(data)
      log.debug (log_key) {"Received #{data.size} bytes from backend."}

      unless @tctp_decryption_requested
        log.debug (log_key) {"Relaying #{data.size} bytes directly to client."}
        send_data data
      else
        # Use either the same HALEC used for sending an HTTP body, or any free HALEC
        @server_halec ||= proxy.halec_registry.halecs(:server).shift[1]
        @server_halec_encrypted_sequence_index ||= @server_halec.data_to_be_encrypted.sequence_index
        @connection_encrypted_data_queue ||= Tresor::TCTP::SequenceQueue.new(@server_halec_encrypted_sequence_index)

        # Need to parse backend response to filter out headers
        unless @client_http_parser
          @client_http_parser = HTTP::Parser.new

          # Relay all headers as is, except for Transfer-Encoding, Content-Encoding. Send HALEC URL as first line of
          # response.
          @client_http_parser.on_headers_complete = proc do |headers|
            send_data "HTTP/1.1 #{@client_http_parser.status_code}\r\n"

            headers.each do |header, value|
              if header.eql?('Transfer-Encoding') || header.eql?('Content-Length')
                @has_body = true

                next
              end

              send_data "#{header}: #{value}\r\n"
            end

            if @has_body
              send_data "Transfer-Encoding: chunked\r\n"
              send_data "Content-Encoding: encrypted\r\n\r\n"

              server_halec_url_plus_line_break_length_as_hex = (@server_halec.url.length + 2).to_s(16)

              send_data "#{server_halec_url_plus_line_break_length_as_hex}\r\n#{@server_halec.url}\r\n"
            end

            send_data "\r\n"
          end

          # Encrypt each part of backend body
          @client_http_parser.on_body = proc do |chunk|
            log.debug (log_key) { "Pushing chunk ##{@server_halec_encrypted_sequence_index} to #data_to_be_encrypted queue." }

            @server_halec.data_to_be_encrypted.push chunk, @server_halec_encrypted_sequence_index
            @server_halec_encrypted_sequence_index += 1

            send_encrypted_data
          end

          @client_http_parser.on_message_complete = proc do
            log.debug (log_key) { "Pushing :eof as chunk ##{@server_halec_encrypted_sequence_index} to #data_to_be_encrypted queue." }

            @server_halec.data_to_be_encrypted.push :eof, @server_halec_encrypted_sequence_index
            @server_halec_encrypted_sequence_index += 1

            send_encrypted_data
          end
        end

        log.debug (log_key) {"Sending #{data.size} bytes to HTTP parser to be encrypted to client."}

        @client_http_parser << data
      end
    end

    def unbind
      log.debug (log_key) { 'closed' }
    end

    def send_error_response(error)
      send_data "HTTP/1.1 502 Bad Gateway\r\n"
      send_data "Content-Length: #{error.size}\r\n"
      send_data "\r\n"
      send_data error
    end

    def send_tctp_discovery_information
      send_data "HTTP/1.1 200 OK\r\n"
      send_data "Content-Type: #{DISCOVERY_MEDIA_TYPE}\r\n"
      send_data "Content-Length: #{DISCOVERY_INFORMATION.length}\r\n\r\n"
      send_data DISCOVERY_INFORMATION
    end

    def log_key
      "Thread #{Thread.list.index(Thread.current)} - #{@proxy.name} - Client #{@client_ip}:#{@client_port}"
    end
  end
end