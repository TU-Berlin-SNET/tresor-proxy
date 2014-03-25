module Tresor
  module Frontend
    module ClaimSSO
      # TODO NameIdentifier is only valid in connection with original issuer
      class ClaimSSOSecurityToken
        # The parsed SecurityTokenResponse
        # @return [Nokogiri::XML::Document]
        # @!attr [r] parsed
        attr :parsed

        def initialize(xml_string)
          @parsed = Nokogiri.XML(xml_string)
        end

        def name_id
          @parsed.xpath('//assertion:NameID', {'assertion' => 'urn:oasis:names:tc:SAML:2.0:assertion'})[0].text
        end
      end
    end
  end
end