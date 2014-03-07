module Tresor
  module Frontend
    class FrontendHandler
      attr_reader :connection

      # @param [EventMachine::Connection] connection
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
        self.class.name
      end
    end
  end
end