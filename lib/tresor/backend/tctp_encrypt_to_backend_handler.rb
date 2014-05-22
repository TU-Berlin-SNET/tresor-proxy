class Tresor::Backend::TCTPEncryptToBackendHandler < Tresor::Backend::RelayingBackendHandler
  # Initializes the Handler to encrypt to the +backend+ using the +halec_promise+ promise.
  # @param backend [Tresor::Backend::Backend] The backend
  # @param halec_promise [Tresor::TCTP::HALECRegistry::HALECPromise] The promise
  def initialize(backend, halec_promise)
    @first_chunk = true
    @message_complete = false
    @halec_promise = halec_promise

    super(backend)
  end

  def send_headers_to_backend_connection
    start_line = build_start_line

    log.debug (log_key) { "Encrypting to backend: #{start_line[0..-2]}" }

    tctp_cookie = backend.proxy.halec_registry.get_tctp_cookie(backend.client_connection.host)
    tctp_cookie_sent = false

    backend_connection.send_data start_line

    headers = []
    backend.client_connection.client_headers.each do |header, value|
      next if header.eql?('Accept-Encoding') || header.eql?('Content-Length')

      if header.eql?('Cookie') && tctp_cookie
        headers << {'Cookie' => "#{value};#{tctp_cookie}"}
        tctp_cookie_sent = true

        # Do not send double cookies
        next
      end

      # Send Host header of reverse URL
      if header.eql? 'Host'
        headers << {'Host' => @backend.host}
      else
        headers << {header => value}
      end
    end

    if backend.client_connection.client_headers.has_key? 'Content-Length'
      headers << {'Transfer-Encoding' => 'chunked'}
      headers << {'Content-Encoding' => 'encrypted'}
    end

    headers << {'Cookie' => tctp_cookie} unless tctp_cookie_sent
    headers << {'Accept-Encoding' => 'encrypted'}

    send_client_headers headers

    backend_connection.send_data "\r\n"
  end

  def on_backend_headers_complete(backend_headers)
    relay "HTTP/1.1 #{backend_connection.http_parser.status_code}\r\n"

    @encrypted_response = backend_headers['Content-Encoding'] && backend_headers['Content-Encoding'].eql?('encrypted')

    @has_body = backend_headers['Transfer-Encoding'] || (backend_headers['Content-Length'] && !backend_headers['Content-Length'].eql?("0"))

    headers = []
    backend_headers.each do |header, value|
      # TODO merge Content-Encodings
      if @encrypted_response && %w[Transfer-Encoding Content-Encoding Content-Length].include?(header)
        next
      end

      headers << {header => value}
    end

    if @encrypted_response
      headers << {'Transfer-Encoding' => 'chunked'}
    else
      log.warn (log_key) {"Got unencrypted response from #{backend.client_connection.host} (#{backend_connection.connection_pool_key}) for encrypted request #{build_start_line}!"}

      @halec_promise.return
    end

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

        #TODO Handle HALEC missing exception

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
    log.debug (log_key) { "Finished receiving backend response to #{backend.client_connection.http_method} #{backend.client_connection.path}#{backend.client_connection.query ? "?#{backend.client_connection.query}": ''}." }

    if @encrypted_response
      finish_response
    else
      relay "0\r\n\r\n" if @has_body
    end
  end

  def on_unbind
    @halec_promise.return
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

    @halec_promise.return

    relay "0\r\n\r\n" if @has_body
  end

  def client_chunk(data)
    log.debug (log_key) { "Encrypting #{data.length} bytes to backend." }

    @request_has_body = true

    unless @halec
      @halec = @halec_promise.redeem_halec

      @halec_url_line = "#{@halec.url}\r\n"

      chunk_length_as_hex = @halec_url_line.length.to_s(16)
      chunk = "#{chunk_length_as_hex}\r\n#{@halec_url_line}\r\n"

      backend_connection.send_data chunk
    end

    @halec.encrypt_data_async(data) do |encrypted_data|
      EM.schedule do
        chunk_length_as_hex = encrypted_data.length.to_s(16)

        log.debug (log_key) { "Sending #{encrypted_data.length} (#{chunk_length_as_hex}) bytes of encrypted data from backend to client" }

        chunk = "#{chunk_length_as_hex}\r\n#{encrypted_data}\r\n"

        backend_connection.send_data chunk
      end
    end
  end

  def on_client_message_complete
    if @request_has_body
      @halec.call_async do
        EM.schedule do
          backend_connection.send_data "0\r\n\r\n"
        end
      end
    end

    @halec_promise.return
  end

  def receive_data(data)
    log.debug (log_key) { "Feeding #{data.length} bytes of encrypted data to HTTP parser" }

    @http_parser << data
  end

  def log_key
    "#{@backend.proxy.name} - #{@backend.log_key} - TCTP Encrypt to Backend handler"
  end
end