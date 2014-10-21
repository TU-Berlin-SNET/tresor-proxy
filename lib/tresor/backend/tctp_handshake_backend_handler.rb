class Tresor::Backend::TCTPHandshakeBackendHandler < Tresor::Backend::BackendHandler
  # @param [Tresor::Backend::Backend]
  def initialize(backend)
    super(backend)

    @halec = Rack::TCTP::ClientHALEC.new
    @halec.queue = EventMachine::Queue.new
    @halec.engine.read
    client_hello = @halec.engine.extract

    @tctp_key = request.effective_backend_scheme_authority

    @handshake_url = Tresor::TCTP.handshake_url(@tctp_key, request.effective_backend_request_url)

    @tctp_cookie = backend.proxy.halec_registry.get_tctp_cookies(@tctp_key).first
    @halec.tctp_session_cookie = @tctp_cookie

    backend_connection_future.callback do |backend_connection|
      backend_connection.send_data "POST #{@handshake_url} HTTP/1.1\r\n"
      backend_connection.send_data "Host: #{request.effective_backend_host}\r\n"
      backend_connection.send_data "Cookie: #{@tctp_cookie}\r\n" if @tctp_cookie
      backend_connection.send_data "Content-Length: #{client_hello.length}\r\n"
      backend_connection.send_data "Content-Type: application/octet-stream\r\n\r\n"
      backend_connection.send_data client_hello

      log.debug (log_key) {"POSTed #{client_hello.length} bytes client_hello to #{@handshake_url} of host #{@tctp_key}"}
    end
  end

  def on_backend_headers_complete(headers)
    # TODO Error handling in handshake, e.g., fallback to regular or send error
    if headers['Location']
      @halec.url = URI(headers['Location'])
      log.debug (log_key) {"Got new HALEC url: #{@halec.url}"}
    end

    if headers['Set-Cookie']
      @tctp_cookie = headers['Set-Cookie'].split(/\;/)[0]

      log.debug (log_key) {"Got HALEC cookie: #{@tctp_cookie}"}

      backend.proxy.halec_registry.register_tctp_cookie(@tctp_key, @tctp_cookie)

      @halec.tctp_session_cookie = @tctp_cookie
    end

    if @halec.url
      backend.proxy.halec_registry.register_halec @handshake_url, @halec
    end
  end

  def on_backend_body(chunk)
    log.debug (log_key) {"Got #{chunk.length} bytes handshake response in HTTP body"}

    begin
      @halec.engine.inject chunk
      @halec.engine.read

      if(@halec.engine.state.eql? 'SSLOK ')
        log.debug (log_key) { "TCTP Handshake complete. HALEC #{@halec.url} ready for encrypting data. Popping queue."}

        @halec.start_queue_popping
      end
    rescue Exception => e
      # Invalid handshake data received. Set @last_response to true in order to redecide handler
      @last_response = true
    end
  end

  def on_backend_message_complete
    if(@last_response)
      backend.decide_handler
    else
      handshake_response = @halec.engine.extract

      log.debug (log_key) { "POSTing #{handshake_response.length} bytes client handshake response to HALEC URL #{@halec.url}" }

      backend_connection_future.callback do |backend_connection|
        backend_connection.send_data "POST #{@halec.url.path} HTTP/1.1\r\n"
        backend_connection.send_data "Host: #{request.effective_backend_host}\r\n"
        backend_connection.send_data "Cookie: #{@tctp_cookie}\r\n" if @tctp_cookie
        backend_connection.send_data "Content-Length: #{handshake_response.length}\r\n"
        backend_connection.send_data "Content-Type: application/octet-stream\r\n\r\n"
        backend_connection.send_data handshake_response
      end

      @last_response = true
    end
  end

  def log_key
    "Thread #{Thread.list.index(Thread.current)} - #{@backend.proxy.name} - TCTP Handshake Handler"
  end
end