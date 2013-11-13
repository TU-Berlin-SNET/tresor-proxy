require_relative 'backend_handler'

module Tresor
  module Backend
    class RelayingBackendHandler < BackendHandler
      def initialize(backend)
        @backend = backend

        @http_parser = HTTP::Parser.new

        @http_parser.on_message_complete = proc do |env|
          @backend.free_backend
        end

        start_line = build_start_line

        log.debug (log_key) { "Relaying to backend: #{start_line}" }

        backend.send_data start_line
        backend.client_headers.each do |header, value|
          backend.send_data "#{header}: #{value}\r\n"
        end
        backend.send_data "\r\n"

        @backend.client_chunk_future.succeed self
        @backend.receive_data_future.succeed self
      end

      def receive_data(data)
        @backend.plexer.relay_from_backend data

        @http_parser << data
      end

      def client_chunk(chunk)
        backend.send_data chunk
      end

      def log_key
        "Relay Handler"
      end
    end
  end
end