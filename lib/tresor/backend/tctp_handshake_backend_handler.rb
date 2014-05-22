class Tresor::Backend::TCTPHandshakeBackendHandler < Tresor::Backend::BackendHandler
  # @param [Tresor::Backend::Backend]
  def initialize(backend)
    super(backend)

    @halec = Rack::TCTP::ClientHALEC.new
    @halec.engine.read
    client_hello = @halec.engine.extract

    @handshake_url = Tresor::TCTP.handshake_url(backend.client_connection.host, backend.client_connection.path)

    backend_connection_future.callback do |backend_connection|
      backend_connection.send_data "POST #{@handshake_url} HTTP/1.1\r\n"
      backend_connection.send_data "Host: #{backend.client_connection.host}\r\n"
      backend_connection.send_data "Content-Length: #{client_hello.length}\r\n"
      backend_connection.send_data "Content-Type: application/octet-stream\r\n\r\n"
      backend_connection.send_data client_hello

      log.debug (log_key) {"POSTed #{client_hello.length} bytes client_hello to #{@handshake_url} of host #{backend.client_connection.host}"}
    end
  end

  def on_backend_headers_complete(headers)
    # TODO Error handling in handshake, e.g., fallback to regular or send error
    if headers['Location']
      @halec.url = URI(headers['Location'])
      log.debug (log_key) {"Got new HALEC url: #{@halec.url}"}
    end

    if headers['Set-Cookie']
      @cookie = headers['Set-Cookie'].split(/\;/)[0]

      log.debug (log_key) {"Got HALEC cookie: #{@cookie}"}

      backend.proxy.halec_registry.register_tctp_cookie(backend.client_connection.host, @cookie)
    end
  end

  def on_backend_body(chunk)
    log.debug (log_key) {"Got #{chunk.length} bytes handshake response in HTTP body"}

    @halec.engine.inject chunk
    @halec.engine.read

    if(@halec.engine.state.eql? 'SSLOK ')
      log.debug (log_key) { "TCTP Handshake complete. HALEC #{@halec.url} ready for encrypting data"}

      backend.proxy.halec_registry.register_halec @handshake_url, @halec
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
        backend_connection.send_data "Host: #{backend.client_connection.host}\r\n"
        backend_connection.send_data "Cookie: #{@cookie}\r\n" if @cookie
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