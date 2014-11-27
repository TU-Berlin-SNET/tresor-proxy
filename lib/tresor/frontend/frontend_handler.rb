module Tresor
  module Frontend
    class FrontendHandler
      # The client connection
      # @return [Tresor::Proxy::Connection]
      attr_reader :connection

      # @param [Tresor::Proxy::Connection] connection
      def initialize(connection)
        @connection = connection
      end

      def on_body(chunk)
        throw "implementation for #on_body is missing"
      end

      def on_message_complete()
        throw "implementation for #on_message_complete is missing"
      end

      def log_key
        "#{connection.log_key} - #{self.class.name.demodulize}"
      end

      def proxy
        @connection.proxy
      end
    end
  end
end