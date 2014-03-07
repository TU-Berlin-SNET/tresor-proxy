require 'rack/tctp/halec'

module Tresor::Proxy
  ##
  # A connection from the user agent to the TRESOR proxy
  class Connection < EventMachine::Connection
    class << self
      def frontend_handler_classes
        # TODO Add handlers depending on Proxy configuration, e.g. TCTP or XACML
        @available_frontend_handlers ||= [
            Tresor::Frontend::TCTPDiscoveryFrontendHandler,
            Tresor::Frontend::TCTPHalecCreationFrontendHandler,
            Tresor::Frontend::TCTPHandshakeFrontendHandler,
            Tresor::Frontend::HTTPEncryptingRelayFrontendHandler,
            Tresor::Frontend::HTTPRelayFrontendHandler
        ]
      end
    end

    attr_accessor :http_parser

    attr :client_ip
    attr :client_port

    attr_accessor :proxy

    # The handler, which is used to serve the client request.
    # @!attr [rw] frontend_handler The frontend handler
    # @return [Tresor::Frontend::FrontendHandler] The handler
    attr_accessor :frontend_handler

    def initialize(proxy)
      @proxy = proxy

      reset_http_parser
    end

    def reset_http_parser
      @http_parser = HTTP::Parser.new

      # Create backend as soon as all headers are complete
      @http_parser.on_headers_complete = proc do
        log.debug (log_key) {"Headers complete. Request is #{@http_parser.http_method} #{@http_parser.request_url} HTTP/1.1"}

        decide_frontend_handler
      end

      @http_parser.on_body = proc do |chunk|
        frontend_handler.on_body chunk
      end

      @http_parser.on_message_complete = proc do |env|
        frontend_handler.on_message_complete
      end
    end

    def decide_frontend_handler
      @frontend_handler = nil

      frontend_handler_class = Connection.frontend_handler_classes.find {|h| h.can_handle? self}

      @frontend_handler = frontend_handler_class.new(self)

      if @frontend_handler == nil
        throw Exception.new("No frontend handler can handle request!")
      end
    end

    def post_init
      @client_port, @client_ip = Socket.unpack_sockaddr_in(get_peername)

      log.debug (log_key) {"Connection initialized"}
    end

    def receive_data(data)
      log.debug (log_key) {"Received #{data.size} bytes from client."}

      puts "\r\n#{data}" if proxy.output_raw_data

      @http_parser << data
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

    def send_data(data)
      puts "\r\n#{data}" if proxy.output_raw_data

      super(data)
    end

    def log_key
      "#{@proxy.name} - Client #{@client_ip}:#{@client_port}"
    end
  end
end