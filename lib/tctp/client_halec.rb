require 'eventmachine'
require 'io/wait'

require_relative 'halec'

module Tresor
  module TCTP
    class ClientHALEC < Tresor::TCTP::HALEC
      def initialize(options = {})
        super(options)

        @ssl_socket = OpenSSL::SSL::SSLSocket.new(@socket_here, @ctx)

        Thread.new do
          @ssl_socket.connect

          log.debug(log_key) {'SSL Socket connected.'}

          @halec_handshake_complete.succeed
        end
      end
    end
  end
end