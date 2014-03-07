class Tresor::Backend::TCTPEncryptToBackendHandler < Tresor::Backend::BackendHandler
  def async_action_queue
    @async_action_queue ||= Queue.new
  end

  # Initializes the Handler to encrypt to the +backend+ using the +halec_promise+ promise.
  # @param backend [Tresor::Backend::BasicBackend] The backend
  # @param halec_promise [Tresor::TCTP::HALECRegistry::HALECPromise] The promise
  def initialize(backend, halec_promise)
    @backend = backend
    @halec_promise = halec_promise

    @http_parser = HTTP::Parser.new

    start_line = build_start_line

    log.debug (log_key) { "Encrypting to backend: #{start_line[0..-2]}" }

    cookie = @backend.proxy.halec_registry.get_tctp_cookie(backend.host)
    tctp_cookie_sent = false

    EM.defer do
      while true
        async_action_queue.pop.call
      end
    end

    @backend.send_data start_line
    @backend.client_headers.each do |header, value|
      next if header.eql?('Accept-Encoding') || header.eql?('Content-Length')
      if header.eql?('Cookie') && cookie
        value = "#{value}; #{cookie}"
        tctp_cookie_sent = true
      end

      # Send Host header of reverse URL
      if header.eql? 'Host'
        value = @backend.host
      end

      @backend.send_data "#{header}: #{value}\r\n"
    end
    @backend.send_data "Transfer-Encoding: chunked\r\nContent-Encoding: encrypted\r\n" if @backend.client_headers.has_key? 'Content-Length'
    @backend.send_data "Cookie: #{cookie}\r\n" unless tctp_cookie_sent
    @backend.send_data 'Accept-Encoding: encrypted'
    @backend.send_data "\r\n\r\n"

    @http_parser.on_headers_complete = proc do |headers|
      @backend.plexer.relay_from_backend "HTTP/1.1 #{@http_parser.status_code}\r\n"

      headers.each do |header, value|
        if %w[Transfer-Encoding Content-Length].include? header
          @has_body = true

          next
        end

        if header.eql? 'Content-Encoding'
          @encrypted_response = value.eql? 'encrypted'
        else
          @backend.plexer.relay_from_backend "#{header}: #{value}\r\n"
        end
      end

      unless @encrypted_response
        log.warn (log_key) {"Got unencrypted response from #{backend.host} (#{backend.connection_pool_key}) for encrypted request #{build_start_line}!"}
      end

      @backend.plexer.relay_from_backend "Transfer-Encoding: chunked\r\n" if @has_body

      @backend.plexer.relay_from_backend "\r\n"
    end

    @first_chunk = true
    @message_complete = false

    @http_parser.on_body = proc do |chunk|
      if(@encrypted_response)
        log.debug (log_key) {"Got #{chunk.length} encrypted bytes HTTP body"}

        # On first chunk: Get the HALEC URL, redeem the promise (get the corresponding HALEC) and set up the HALEC to write
        # unencrypted data as chunks back to the client.
        if @first_chunk
          first_newline_index = chunk.index("\r\n")
          body_halec_url = chunk[0, first_newline_index]

          log.debug (log_key) { "Body was encrypted using HALEC #{body_halec_url}" }

          @halec = @halec_promise.redeem_halec(URI(body_halec_url))

          chunk_without_url = chunk[(first_newline_index + 2)..-1]

          unless chunk_without_url.eql?('')
            decrypt_and_relay chunk_without_url
          end

          @first_chunk = false
        else
          decrypt_and_relay chunk
        end
      else
        relay_as_chunked(chunk)
      end
    end

    @http_parser.on_message_complete = proc do |env|
      log.debug (log_key) { "Finished receiving backend response to #{@backend.client_method} #{@backend.client_path}#{@backend.client_query_string ? "?#{@backend.client_query_string}": ''}." }

      if @encrypted_response
        finish_response
      else
        @backend.plexer.relay_from_backend "0\r\n\r\n"
      end
    end

    EM.schedule do
      @backend.client_chunk_future.succeed self
      @backend.receive_data_future.succeed self
    end
  end

  def decrypt_and_relay(data)
    async_action_queue.push proc { relay_as_chunked @halec.decrypt_data(data) }
  end

  def relay_as_chunked(data)
    unless data.length == 0
      chunk_length_as_hex = data.length.to_s(16)

      log.debug (log_key) { "Relaying #{data.length} (#{chunk_length_as_hex}) bytes of data from backend to client" }

      relay "#{chunk_length_as_hex}\r\n#{data}\r\n"
    end
  end

  def finish_response
    async_action_queue.push proc { do_finish_response }
  end

  def do_finish_response
    log.info (log_key) { 'Sending trailer to client' }

    relay "0\r\n\r\n" if @has_body

    if @encrypted_response
      @halec_promise.return
    end

    @backend.free_backend
  end

  def client_chunk(data)
    async_action_queue.push proc {
      do_client_chunk data
    }
  end

  def do_client_chunk(data)
    if data[-5,5].eql? "0\r\n\r\n"
      @backend.send_data "0\r\n\r\n"

      @halec_promise.return
    else
      log.debug (log_key) { "Encrypting #{data.length} bytes to backend." }

      unless @halec
        @halec = @halec_promise.redeem_halec

        @halec_url_line = "#{@halec.url}\r\n"

        chunk_length_as_hex = @halec_url_line.length.to_s(16)
        chunk = "#{chunk_length_as_hex}\r\n#{@halec_url_line}\r\n"

        @backend.send_data chunk
      end

      encrypted_data = @halec.encrypt_data data

      chunk_length_as_hex = encrypted_data.length.to_s(16)

      log.debug (log_key) { "Sending #{encrypted_data.length} (#{chunk_length_as_hex}) bytes of encrypted data from backend to client" }

      chunk = "#{chunk_length_as_hex}\r\n#{encrypted_data}\r\n"

      @backend.send_data chunk
    end
  end

  def receive_data(data)
    log.debug (log_key) { "Feeding #{data.length} bytes of encrypted data to HTTP parser" }

    @http_parser << data
  end

  def log_key
    "#{@backend.proxy.name} - TCTP Encrypt to Backend handler"
  end
end