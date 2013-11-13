require 'http_parser'
require_relative 'connection_pool'

module Tresor
  ##
  # A connection from the user agent to the TRESOR proxy
  class Connection < EventMachine::Connection
    attr :http_parser

    attr :client_ip
    attr :client_port

    attr_accessor :proxy

    attr :backend_future

    def initialize
      @http_parser = HTTP::Parser.new

      # Create backend as soon as all headers are complete
      @http_parser.on_headers_complete = proc do
        log.debug (log_key) {"Headers complete. Request is #{@http_parser.http_method} #{@http_parser.request_url} HTTP/1.1"}

        if @http_parser.request_url.start_with?('http')
          # Forward proxy
          @backend_future = proxy.connection_pool.get_backend_future_for_forward_url(@http_parser.request_url, self)
        else
          # Reverse proxy
          @backend_future = proxy.connection_pool.get_backend_future_for_reverse_host(@http_parser.headers['Host'], self)
        end

        @backend_future.callback do |backend|
          parsed_uri = URI.parse(@http_parser.request_url)

          # Inform Backend about the current client request
          backend.client_request @http_parser.http_method, parsed_uri.path, parsed_uri.query, @http_parser.headers
        end

        @backend_future.errback do |error|
          send_error_response(error)

          close_connection_after_writing
        end
      end

      @http_parser.on_body = proc do |chunk|
        @backend_future.callback do |backend|
          backend.client_chunk chunk
        end
      end

      @http_parser.on_message_complete = proc do |env|

      end
    end

    def post_init
      @client_port, @client_ip = Socket.unpack_sockaddr_in(get_peername)

      log.debug (log_key) {"Connection initialized"}
    end

    def receive_data(data)
      log.debug (log_key) {"Received #{data.size} bytes from client."}

      @http_parser << data
    end

    def relay_from_backend(data)
      log.debug (log_key) {"Received #{data.size} bytes from backend."}

      send_data data
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

    def log_key
      "Client #{@client_ip}:#{@client_port}"
    end
  end
end