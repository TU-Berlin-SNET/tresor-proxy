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

    # The headers the client sent
    # @return [Hash]
    # @!attr [r] client_headers
    attr :client_headers

    # The current TRESOR proxy instance
    # @return [Tresor::Proxy::TresorProxy]
    attr :proxy

    # The future handler, which is used to serve the client request.
    # @!attr [rw] frontend_handler_future The future frontend handler
    # @return [EventMachine::DefaultDeferrable] The future frontend handler
    attr_accessor :frontend_handler_future

    # The current handler, which is used to serve the client request.
    # @!attr [rw] frontend_handler The frontend handler
    # @return [Tresor::Frontend::FrontendHandler] The handler
    attr_accessor :frontend_handler

    # Additional headers, which are to be relayed to the client.
    # @!attr [rw] additional_headers_to_relay
    # @return [Hash] The additional headers
    attr_accessor :additional_headers_to_relay

    # Initializes the connection by setting the proxy reference and resetting the HTTP parser
    # @param [Tresor::Proxy::Proxy] proxy The proxy reference
    def initialize(proxy)
      @proxy = proxy

      @http_parser = HTTP::Parser.new

      # Create backend as soon as all headers are complete
      http_parser.on_headers_complete = proc do |headers|
        @cookies, @query_vars, @parsed_request_uri = nil, nil, nil

        @client_headers = headers
        @additional_headers_to_relay = {}

        log.debug (log_key) {"Headers complete. Request is #{@http_parser.http_method} #{@http_parser.request_url} HTTP/1.1"}

        decide_frontend_handler
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

      @frontend_handler_future.errback do
        throw Exception.new('No frontend handler can handle request!')
      end

      EM.defer do
        frontend_handler_class = Connection.frontend_handler_classes.find do |h|
          log.debug (log_key) { "Testing frontend handler #{h.name}" }

          h.can_handle? self
        end

        EM.schedule do
          if !frontend_handler_class.eql? NilClass
            log.debug (log_key) { "Set frontend handler to #{frontend_handler_class.name}" }

            @frontend_handler = frontend_handler_class.new(self)

            @frontend_handler_future.succeed @frontend_handler
          else
            @frontend_handler_future.fail
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

    def log_key
      "#{@proxy.name} - Client #{@client_ip}:#{@client_port}"
    end

    def host
      @client_headers['Host']
    end

    def http_method
      http_parser.http_method
    end

    def path
      parsed_request_uri.path
    end

    def query
      parsed_request_uri.query
    end

    # Returns the parsed request URI
    # @return [URI::HTTP]
    def parsed_request_uri
      unless @parsed_request_uri
        @parsed_request_uri = URI.parse(http_parser.request_url)
        @parsed_request_uri.path = '/' if @parsed_request_uri.path.eql?('')
      end

      @parsed_request_uri
    end

    # Uses the HTTP parser to parse the cookies
    # @return [Hash] Cookies as Hash
    def cookies
      unless @cookies
        http_cookie_header = http_parser.headers['Cookie']

        if http_cookie_header
          begin
            @cookies = Hash[http_cookie_header.split(';').map{|c| c.strip.split('=', 2)}]
          rescue Exception
            @cookies = {}
          end
        else
          @cookies = {}
        end
      end

      @cookies
    end

    # Parses the query vars
    # @return [Hash{String => String}]
    def query_vars
      unless @query_vars
        http_query = parsed_request_uri.query

        if http_query
          begin
            @query_vars = Hash[http_query.split('&').map{|q| q.split('=')}]
          rescue Exception
            @query_vars = {}
          end
        else
          @query_vars = {}
        end
      end

      @query_vars
    end

    # Gets the authorized subject ID
    # @return [String]
    def subject_id
      sso_session ? sso_session.name_id : nil
    end

    def subject_attributes
      sso_session ? sso_session.attributes_hash : {}
    end

    # Gets the SSO id, either from cookie or from query string
    def sso_id
      query_vars['tresor_sso_id'] || cookies['tresor_sso_id']
    end

    def sso_session
      if sso_id
        proxy.sso_sessions[sso_id]
      else
        nil
      end
    end
  end
end