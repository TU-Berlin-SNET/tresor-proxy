class Tresor::Backend::TCTPEncryptToBackendHandler < Tresor::Backend::RelayingBackendHandler
  # Initializes the Handler to encrypt to the +backend+ using the +halec_promise+ promise.
  # @param backend [Tresor::Backend::BasicBackend] The backend
  # @param halec_promise [Tresor::TCTP::HALECRegistry::HALECPromise] The promise
  def initialize(backend, halec_promise)
    @first_chunk = true
    @message_complete = false
    @halec_promise = halec_promise

    super(backend)
  end

  def send_request_to_backend
    start_line = build_start_line

    log.debug (log_key) { "Encrypting to backend: #{start_line[0..-2]}" }

    tctp_cookie = @backend.proxy.halec_registry.get_tctp_cookie(backend.host)
    tctp_cookie_sent = false

    @backend.send_data start_line

    headers = []
    @backend.client_headers.each do |header, value|
      next if header.eql?('Accept-Encoding') || header.eql?('Content-Length')

      if header.eql?('Cookie') && tctp_cookie
        headers << {'Cookie' => "#{value}; #{tctp_cookie}"}
        tctp_cookie_sent = true
      end

      # Send Host header of reverse URL
      if header.eql? 'Host'
        headers << {'Host' => @backend.host}
      else
        headers << {header => value}
      end
    end

    if @backend.client_headers.has_key? 'Content-Length'
      headers << {'Transfer-Encoding' => 'chunked'}
      headers << {'Content-Encoding' => 'encrypted'}
    end

    headers << {'Cookie' => tctp_cookie} unless tctp_cookie_sent
    headers << {'Accept-Encoding' => 'encrypted'}

    send_client_headers headers

    @backend.send_data "\r\n"
  end

  def on_backend_headers_complete(backend_headers)
    relay "HTTP/1.1 #{@http_parser.status_code}\r\n"

    headers = []
    backend_headers.each do |header, value|
      if %w[Transfer-Encoding Content-Length].include? header
        @has_body = true

        headers << {header => value}

        next
      end

      if header.eql? 'Content-Encoding'
        @encrypted_response = value.eql? 'encrypted'
      else
        headers << {header => value}
      end
    end

    unless @encrypted_response
      log.warn (log_key) {"Got unencrypted response from #{backend.host} (#{backend.connection_pool_key}) for encrypted request #{build_start_line}!"}
    end

    headers << {'Transfer-Encoding' => 'chunked'} if @has_body

    relay_backend_headers headers

    relay "\r\n"
  end

  def on_backend_body(chunk)
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

  def on_backend_message_complete
    log.debug (log_key) { "Finished receiving backend response to #{@backend.client_method} #{@backend.client_path}#{@backend.client_query_string ? "?#{@backend.client_query_string}": ''}." }

    if @encrypted_response
      finish_response
    else
      relay "0\r\n\r\n"
    end
  end

  def decrypt_and_relay(data)
    @halec.decrypt_data_async(data) do |decrypted_data|
      EM.schedule do
        relay_as_chunked decrypted_data
      end
    end
  end

  def finish_response
    @halec.call_async do
      EM.schedule do
        do_finish_response
      end
    end
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
    if data[-5,5].eql? "0\r\n\r\n"
      @halec.call_async do
        EM.schedule do
          @backend.send_data "0\r\n\r\n"

          @halec_promise.return
        end
      end
    else
      log.debug (log_key) { "Encrypting #{data.length} bytes to backend." }

      unless @halec
        @halec = @halec_promise.redeem_halec

        @halec_url_line = "#{@halec.url}\r\n"

        chunk_length_as_hex = @halec_url_line.length.to_s(16)
        chunk = "#{chunk_length_as_hex}\r\n#{@halec_url_line}\r\n"

        @backend.send_data chunk
      end

      @halec.encrypt_data_async(data) do |encrypted_data|
        EM.schedule do
          chunk_length_as_hex = encrypted_data.length.to_s(16)

          log.debug (log_key) { "Sending #{encrypted_data.length} (#{chunk_length_as_hex}) bytes of encrypted data from backend to client" }

          chunk = "#{chunk_length_as_hex}\r\n#{encrypted_data}\r\n"

          @backend.send_data chunk
        end
      end
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