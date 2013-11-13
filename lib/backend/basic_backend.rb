require 'eventmachine'

require_relative 'relaying_backend_handler'
require_relative 'tctp_discovery_backend_handler'
require_relative 'tctp_handshake_backend_handler'
require_relative 'tctp_encryption_backend_handler'

require_relative '../tctp/halec_registry'

module Tresor
  module Backend
    class BasicBackend < EventMachine::Connection
      attr_accessor :proxy
      attr_accessor :connection_pool_key
      attr_accessor :host
      attr_accessor :plexer

      attr_accessor :client_method
      attr_accessor :client_path
      attr_accessor :client_query_string
      attr_accessor :client_headers

      attr_accessor :backend_handler
      attr_accessor :client_chunk_future
      attr_accessor :receive_data_future

      def initialize
        reset_backend_handler
      end

      def connection_completed

      end

      def receive_data(data)
        log.debug (log_key) { "Received #{data.size} bytes from backend" }

        @receive_data_future.callback do |backend_handler|
          backend_handler.receive_data data
        end
      end

      def unbind

      end

      def free_backend
        reset_backend_handler

        proxy.connection_pool.backend_unbind(connection_pool_key, self)
      end

      # Receives current client request
      def client_request(client_method, client_path, client_query_string, client_headers)
        @client_method = client_method
        @client_path = client_path
        @client_query_string = client_query_string
        @client_headers = client_headers

        decide_handler
      end

      def decide_handler
        if proxy.is_tctp_client
          if Tresor::TCTP.tctp_status_known?(@host)
            if Tresor::TCTP.is_tctp_server?(@host) && Tresor::TCTP.is_tctp_protected?(@host, @client_path)
              begin
                promise = Tresor::TCTP::HALECRegistry.promise_for(@host, @client_path)

                @backend_handler = TCTPEncryptionBackendHandler.new(self, promise)
              rescue Tresor::TCTP::HALECUnavailable
                log.debug (log_key) { "Performing TCTP handshake to create HALEC for #{@host}" }

                # Use this backend connection for TCTP handshake
                @backend_handler = TCTPHandshakeBackendHandler.new(self)
              end
            else
              @backend_handler = RelayingBackendHandler.new(self)
            end
          else
            @backend_handler = TCTPDiscoveryBackendHandler.new(self)
          end
        else
          @backend_handler = RelayingBackendHandler.new(self)
        end
      end

      # Buffer data until the connection to the backend server
      # is established and is ready for use
      def client_chunk(chunk)
        @client_chunk_future.callback do |backend_handler|
          backend_handler.client_chunk chunk
        end
      end

      # Resets the backend handler if backend is reused
      def reset_backend_handler
        @backend_handler = nil

        @client_chunk_future = EventMachine::DefaultDeferrable.new
        @receive_data_future = EventMachine::DefaultDeferrable.new
      end

      def log_key
        "Backend #{@connection_pool_key} #{@host}"
      end
    end
  end
end