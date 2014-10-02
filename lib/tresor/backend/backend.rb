module Tresor
  module Backend
    class Backend
      # The proxy
      # @!attr [r] proxy
      # @return [Tresor::Proxy::TresorProxy]
      attr :proxy

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

        tctp_key = client_connection.request.effective_backend_scheme_authority
        path = client_connection.request.request_url.path

        if proxy.is_tctp_client
          if Tresor::TCTP.tctp_status_known?(tctp_key)
            if Tresor::TCTP.is_tctp_server?(tctp_key) && Tresor::TCTP.is_tctp_protected?(tctp_key, path)
              begin
                promise = @proxy.halec_registry.promise_for(tctp_key, path)

                @backend_handler = TCTPEncryptToBackendHandler.new(self, promise)
              rescue Tresor::TCTP::HALECUnavailable
                log.debug (log_key) { "Performing TCTP handshake to create HALEC for #{tctp_key}" }

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