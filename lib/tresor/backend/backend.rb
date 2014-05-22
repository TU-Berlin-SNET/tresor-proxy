module Tresor
  module Backend
    class Backend
      # The proxy
      # @!attr [r] proxy
      # @return [Tresor::Proxy::TresorProxy]
      attr :proxy
      attr_accessor :host

      # The client connection
      # @return [Tresor::Proxy::Connection] The client connection
      # @!attr [rw] client_connection
      attr_accessor :client_connection

      attr_accessor :backend_handler
      attr_accessor :client_chunk_future

      # @param [Tresor::Proxy::Connection]
      def initialize(client_connection)
        @client_connection = client_connection
        @proxy = client_connection.proxy

        decide_handler

        reset_backend_handler
      end

      # Resets the backend handler if backend is reused
      def reset_backend_handler
        @backend_handler = nil

        @client_chunk_future = EventMachine::DefaultDeferrable.new
      end

      def decide_handler
        log.debug (log_key) { "Deciding Handler" }

        if proxy.is_tctp_client
          if Tresor::TCTP.tctp_status_known?(client_connection.host)
            if Tresor::TCTP.is_tctp_server?(client_connection.host) && Tresor::TCTP.is_tctp_protected?(client_connection.host, client_connection.path)
              begin
                promise = @proxy.halec_registry.promise_for(client_connection.host, client_connection.path)

                @backend_handler = TCTPEncryptToBackendHandler.new(self, promise)
              rescue Tresor::TCTP::HALECUnavailable
                log.debug (log_key) { "Performing TCTP handshake to create HALEC for #{client_connection.host}" }

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
          EM.schedule do
            if chunk.eql? :last
              backend_handler.on_client_message_complete
            else
              backend_handler.client_chunk chunk
            end
          end
        end
      end

      def log_key
        "#{client_connection.log_key} - Backend - Thread #{Thread.list.index(Thread.current)}"
      end
    end
  end
end