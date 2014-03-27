class Tresor::Backend::TCTPHandshakeBackendHandler < Tresor::Backend::BackendHandler
  def initialize(backend)
    @backend = backend

    @halec = Rack::TCTP::ClientHALEC.new

    @http_parser = HTTP::Parser.new
    @http_parser.on_headers_complete = proc do |headers|
      # TODO Error handling in handshake, e.g., fallback to regular or send error
      if headers['Location']
        @halec.url = URI(headers['Location'])
        log.debug (log_key) {"Got new HALEC url: #{@halec.url}"}
      end

      if headers['Set-Cookie']
        @cookie = headers['Set-Cookie'].split(/\;/)[0]

        log.debug (log_key) {"Got HALEC cookie: #{@cookie}"}

        @backend.proxy.halec_registry.register_tctp_cookie(@backend.host, @cookie)
      end
    end

    @http_parser.on_body = proc do |chunk|
      log.debug (log_key) {"Got #{chunk.length} bytes handshake response in HTTP body"}

      @halec.engine.inject chunk
      @halec.engine.read

      if(@halec.engine.state.eql? 'SSLOK ')
        log.debug (log_key) { "TCTP Handshake complete. HALEC #{@halec.url} ready for encrypting data"}

        @backend.proxy.halec_registry.register_halec @handshake_url, @halec
      end
    end

    @http_parser.on_message_complete = proc do |env|
      handshake_response = @halec.engine.extract

      log.debug (log_key) { "POSTing #{handshake_response.length} bytes client handshake response to HALEC URL #{@halec.url}" }

      @http_parser.on_message_complete = proc do
        @backend.decide_handler
      end

      @backend.send_data "POST #{@halec.url.path} HTTP/1.1\r\n"
      @backend.send_data "Host: #{@backend.host}\r\n"
      @backend.send_data "Cookie: #{@cookie}\r\n" if @cookie
      @backend.send_data "Content-Length: #{handshake_response.length}\r\n"
      @backend.send_data "Content-Type: application/octet-stream\r\n\r\n"

      @backend.send_data handshake_response
    end

    @halec.engine.read
    client_hello = @halec.engine.extract

    @handshake_url = Tresor::TCTP.handshake_url(@backend.host, @backend.client_path)

    @http_parser.reset!

    @backend.send_data "POST #{@handshake_url} HTTP/1.1\r\n"
    @backend.send_data "Host: #{@backend.host}\r\n"
    @backend.send_data "Cookie: #{@cookie}\r\n" if @cookie
    @backend.send_data "Content-Length: #{client_hello.length}\r\n"
    @backend.send_data "Content-Type: application/octet-stream\r\n\r\n"
    @backend.send_data client_hello

    log.debug (log_key) {"POSTed #{client_hello.length} bytes client_hello to #{@handshake_url} of host #{@backend.host}"}

    @backend.receive_data_future.succeed self
  end

  def receive_data(data)
    log.debug (log_key) { "Feeding #{data.length} bytes of handshake data to HTTP parser" }

    @http_parser << data
  end

  def log_key
    "Thread #{Thread.list.index(Thread.current)} - #{@backend.proxy.name} - TCTP Handshake Handler"
  end
end