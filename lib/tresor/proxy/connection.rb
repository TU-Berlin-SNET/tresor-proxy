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
        @available_frontend_handlers ||= [
            Tresor::Frontend::TCTPDiscoveryFrontendHandler,
            Tresor::Frontend::TCTPHalecCreationFrontendHandler,
            Tresor::Frontend::TCTPHandshakeFrontendHandler,
            Tresor::Frontend::HTTPEncryptingRelayFrontendHandler,
            Tresor::Frontend::HTTPRelayFrontendHandler
        ]
      end
    end

    # The HTTP parser used for parsing the client request
    # @return [HTTP::Parser]
    # @!attr [r] http_parser
    attr :http_parser

    # The IP address of the connected client
    # @return [String]
    # @!attr [r] client_ip
    attr :client_ip

    # The port of the connected client
    # @return [Integer]
    # @!attr [r] client_port
    attr :client_port

    # The current TRESOR proxy instance
    # @return [Tresor::Proxy::Proxy]
    attr :proxy

    # The handler, which is used to serve the client request.
    # @!attr [rw] frontend_handler The frontend handler
    # @return [Tresor::Frontend::FrontendHandler] The handler
    attr_accessor :frontend_handler

    # Initializes the connection by setting the proxy reference and resetting the HTTP parser
    # @param [Tresor::Proxy::Proxy] proxy The proxy reference
    def initialize(proxy)
      @proxy = proxy

      @http_parser = HTTP::Parser.new

      # Create backend as soon as all headers are complete
      http_parser.on_headers_complete = proc do
        log.debug (log_key) {"Headers complete. Request is #{@http_parser.http_method} #{@http_parser.request_url} HTTP/1.1"}

        decide_frontend_handler
      end

      http_parser.on_body = proc do |chunk|
        frontend_handler.on_body chunk
      end

      http_parser.on_message_complete = proc do |env|
        frontend_handler.on_message_complete
      end
    end

    def decide_frontend_handler
      @frontend_handler = nil

      frontend_handler_class = Connection.frontend_handler_classes.find {|h| h.can_handle? self}

      throw Exception.new("No frontend handler can handle request!") unless frontend_handler_class

      @frontend_handler = frontend_handler_class.new(self)
    end

    def post_init
      @client_port, @client_ip = Socket.unpack_sockaddr_in(get_peername)

      log.debug (log_key) {"Connection initialized"}
    end

    def receive_data(data)
      log.debug (log_key) {"Received #{data.size} bytes from client."}

      puts "\r\n#{data}" if proxy.output_raw_data

      http_parser << data
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