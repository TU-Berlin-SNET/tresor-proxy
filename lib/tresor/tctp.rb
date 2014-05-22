module Tresor
  module TCTP
    extend ActiveSupport::Autoload

    autoload :HALECRegistry
    autoload :DiscoveryInformation

    ActiveSupport::Dependencies.load_file File.join(__dir__, 'tctp', 'halec_extension.rb')

    # Discovered TCTP information
    @@host_discovery_information = {}

    def self.tctp_status_known?(host)
      @@host_discovery_information.has_key? host
    end

    def self.is_tctp_server?(host)
      @@host_discovery_information[host] != false
    end

    def self.is_tctp_protected?(host, url)
      handshake_url(host, url) != false
    end

    def self.handshake_url(host, resource_url)
      return unless is_tctp_server? host

      host_discovery_information[host].paths.each do |regexp, handshake_url|
        if(regexp.match(resource_url).size > 0)
          return handshake_url
        end
      end
    end

    def self.host_discovery_information
      @@host_discovery_information
    end
  end
end