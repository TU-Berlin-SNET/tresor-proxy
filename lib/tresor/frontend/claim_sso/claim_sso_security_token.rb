require 'nokogiri'

module Tresor
  module Frontend
    module ClaimSSO
      # TODO NameIdentifier is only valid in connection with original issuer
      class ClaimSSOSecurityToken
        # The parsed SecurityTokenResponse
        # @return [Nokogiri::XML::Document]
        # @!attr [r] parsed
        attr :parsed

        attr_accessor :tresor_organization_uuid

        def initialize(xml_string)
          @parsed = Nokogiri.XML(xml_string)
        end

        def name_id
          @parsed.xpath('//assertion:NameID', {'assertion' => 'urn:oasis:names:tc:SAML:2.0:assertion'})[0].text
        end

        def organization
          organizations = attributes_hash['http://schemas.tresor.com/claims/2014/04/organization']

          organizations ? organizations[0] : nil
        end

        def attributes
          @parsed.xpath('//assertion:AttributeStatement/assertion:Attribute', {'assertion' => 'urn:oasis:names:tc:SAML:2.0:assertion'})
        end

        def attributes_hash
          attribute_statements = Hash[attributes.map {|a| [a['Name'], a.children.map(&:text)]}]

          userdata = attribute_statements["http://schemas.microsoft.com/ws/2008/06/identity/claims/userdata"]

          if userdata
            skidentity_attributes = Hash[userdata.map { |data| [data.split(':')[0..-2].join(':'), [data.split(':')[-1]]] }]

            attribute_statements.merge!(skidentity_attributes)

            eid = skidentity_attributes['http://www.skidentity.de/att/eIdentifier']

            %w[hpc-id npa-id egk-id].each do |id|
              attribute_statements["http://schemas.cloud-tresor.com/schema/2014/11/#{id}"] = [eid]
            end
          end

          attribute_statements
        end
      end
    end
  end
end