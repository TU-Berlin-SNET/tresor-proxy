require 'http_parser'
require_relative 'connection_pool'

module Tresor
  ##
  # A connection from the user agent to the TRESOR proxy
  class Connection < EventMachine::Connection
    attr :http_parser

    attr :client_ip
    attr :client_port

    attr :backend_future

    def initialize
      @http_parser = HTTP::Parser.new

      @http_parser.on_headers_complete = proc do
        @backend_future = Tresor::ConnectionPool.get_backend_future_for_host(@http_parser.headers['Host'], self)

        @backend_future.callback do |backend|
          send_http_header backend
        end
      end

      @http_parser.on_body = proc do |chunk|
        @backend_future.send_upstream chunk
      end

      @http_parser.on_message_complete = proc do |env|

      end
    end

    def post_init
      @client_port, @client_ip = Socket.unpack_sockaddr_in(get_peername)
    end

    def receive_data(data)
      @http_parser << data
    end

    def relay_from_backend(data)
      send_data data
    end

    def unbind

    end

    # Send the HTTP headers from the client to the backend
    def send_http_header(backend)
      backend.send_upstream "#{@http_parser.http_method} #{@http_parser.request_url} HTTP/1.1\r\n"
      @http_parser.headers.each do |header, value|
        backend.send_upstream "#{header}: #{value}\r\n"
      end

      backend.send_upstream "\r\n"
    end
  end
end