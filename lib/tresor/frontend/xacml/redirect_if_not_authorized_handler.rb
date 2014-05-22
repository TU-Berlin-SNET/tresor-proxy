require 'nokogiri'

module Tresor
  module Frontend
    module XACML
      class RedirectIfNotAuthorizedHandler < Tresor::Frontend::FrontendHandler
        class << self
          # @param [Tresor::Proxy::Connection] connection
          def can_handle?(connection)
            #connection.proxy.is_xacml_enabled &&
            #!connection.http_parser.headers['Host'].start_with?(connection.proxy.hostname)

            false
          end
        end

        # @param [Tresor::Proxy::Connection] connection
        def initialize(connection)
          super(connection)
        end
      end
    end
  end
end