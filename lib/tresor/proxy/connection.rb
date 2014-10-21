require 'rack/tctp/halec'

module Tresor::Proxy
  ##
  # This is the main Connection implementation of the TRESOR proxy.
  #
  # After parsing the HTTP headers, it uses a FrontendHandler for handling requests.
  class Connection < EventMachine::Connection
    class << self
      # Returns an array of available frontend handler classes. These classes are
      # iterated to find a respective handler class for handling a client request.
      # @return [Array[Class]] Available frontend handler classes
      def frontend_handler_classes
        # TODO Add handlers depending on Proxy configuration, e.g. TCTP or XACML
        [
            Tresor::Frontend::NotSupportedRequestHandler,
            Tresor::Frontend::TCTPDiscoveryFrontendHandler,
            Tresor::Frontend::TCTPHalecCreationFrontendHandler,
            Tresor::Frontend::TCTPHandshakeFrontendHandler,
            Tresor::Frontend::ClaimSSO::RedirectToSSOFrontendHandler,
            Tresor::Frontend::ClaimSSO::ProcessSAMLResponseFrontendHandler,
            Tresor::Frontend::TresorProxyFrontendHandler,
            Tresor::Frontend::XACML::DenyIfNotAuthorizedHandler,
            Tresor::Frontend::HTTPEncryptingRelayFrontendHandler,
            Tresor::Frontend::HTTPRelayFrontendHandler
        ]
      end
    end

    # The IP address of the connected client
    # @return [String]
    # @!attr [r] client_ip
    attr :client_ip

    # The port of the connected client
    # @return [Integer]
    # @!attr [r] client_port
    attr :client_port

    # The current TRESOR proxy instance
    # @return [Tresor::Proxy::TresorProxy]
    attr :proxy

    # The current request
    # @!attr [rw] request
    # @return [Tresor::Proxy::Request]
    attr_accessor :request

    # The future handler, which is used to serve the client request.
    # @!attr [rw] frontend_handler_future The future frontend handler
    # @return [EventMachine::DefaultDeferrable] The future frontend handler
    attr_accessor :frontend_handler_future

    # The current handler, which is used to serve the client request.
    # @!attr [rw] frontend_handler The frontend handler
    # @return [Tresor::Frontend::FrontendHandler] The handler
    attr_accessor :frontend_handler

    # Initializes the connection by setting the proxy reference and resetting the HTTP parser
    # @param [Tresor::Proxy::Proxy] proxy The proxy reference
    def initialize(proxy)
      @proxy = proxy

      @http_parser = HTTP::Parser.new

      # Create backend as soon as all headers are complete
      http_parser.on_headers_complete = proc do |headers|
        begin
          @request = Tresor::Proxy::Request.new(self, @http_parser)

          log.debug (log_key) {"Headers complete. Request is #{@request.http_method} #{@request.request_url} HTTP/1.1"}

          decide_frontend_handler
        rescue Exception => e
          send_error_response e
        end
      end

      http_parser.on_body = proc do |chunk|
        frontend_handler_future.callback do |frontend_handler|
          frontend_handler.on_body chunk
        end
      end

      http_parser.on_message_complete = proc do |env|
        frontend_handler_future.callback do |frontend_handler|
          frontend_handler.on_message_complete
        end
      end
    end

    def decide_frontend_handler
      @frontend_handler_future = EM::DefaultDeferrable.new

      @frontend_handler_future.errback do |error|
        send_error_response error
      end

      EM.defer do
        frontend_handler_class = Connection.frontend_handler_classes.find do |h|
          log.debug (log_key) { "Testing frontend handler #{h.name}" }

          h.can_handle? self
        end

        EM.schedule do
          if frontend_handler_class.present?
            log.debug (log_key) { "Set frontend handler to #{frontend_handler_class.name}" }

            @frontend_handler = frontend_handler_class.new(self)

            @frontend_handler_future.succeed @frontend_handler
          else
            @frontend_handler_future.fail Exception.new('Cannot forward request.')
          end
        end
      end
    end

    def post_init
      @client_port, @client_ip = Socket.unpack_sockaddr_in(get_peername)

      log.debug (log_key) {"Connection initialized"}

      if @proxy.tls
        start_tls :private_key_file => proxy.tls_key, :cert_chain_file => proxy.tls_crt, :verify_peer => false
      end
    end

    def receive_data(data)
      log.debug (log_key) {"Received #{data.size} bytes from client."}

      puts "\r\n#{data}" if proxy.output_raw_data

      begin
        http_parser << data
      rescue Exception => e
        log.error e
        log.debug data

        send_error_response e
      end
    end

    def unbind
      log.debug (log_key) { 'closed' }
    end

    # @param [Exception] error
    def send_error_response(error)
      send_data "HTTP/1.1 502 Bad Gateway\r\n"
      send_data "Content-Length: #{error.message.size}\r\n"
      send_data "\r\n"
      send_data error.message
    end

    def send_data(data)
      puts "\r\n#{data}" if proxy.output_raw_data

      super(data)
    end

    def relay_additional_headers
      request.additional_headers_to_relay.each do |hash|
        send_data "#{hash.keys.first}: #{hash.values.first}\r\n"
      end
    end

    def log_key
      "#{@proxy.name} - Client #{@client_ip}:#{@client_port}"
    end

    # The HTTP parser used for parsing the client request
    # @return [HTTP::Parser]
    # @!attr [r] http_parser
    private
      attr :http_parser
  end
end