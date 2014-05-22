require 'rack'

module Tresor
  class XACMLPDPMockServer
    DENY_RESPONSE = '<Response xmlns="urn:oasis:names:tc:xacml:3.0:core:schema:wd-17"><Result><Decision>Deny</Decision><Status><StatusCode Value="urn:oasis:names:tc:xacml:1.0:status:ok"/></Status></Result></Response>'

    PERMIT_RESPONSE = '<Response xmlns="urn:oasis:names:tc:xacml:3.0:core:schema:wd-17"><Result><Decision>Permit</Decision><Status><StatusCode Value="urn:oasis:names:tc:xacml:1.0:status:ok"/></Status></Result></Response>'

    class << self
      attr_accessor :mock_action
    end

    def call(env)
      if XACMLPDPMockServer.mock_action == :permit
        [ 200, {'Content-Type' => 'application/xml;charset=ISO-8859-1', 'Content-Length' => PERMIT_RESPONSE.length.to_s}, [PERMIT_RESPONSE]]
      else
        [ 200, {'Content-Type' => 'application/xml;charset=ISO-8859-1', 'Content-Length' => DENY_RESPONSE.length.to_s}, [DENY_RESPONSE]]
      end
    end
  end
end