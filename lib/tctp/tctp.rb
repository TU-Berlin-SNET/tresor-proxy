module Tresor
  module TCTP
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

    class DiscoveryInformation
      attr_accessor :paths
      attr_accessor :raw_data

      def initialize
        @paths = {}
        @raw_data = StringIO.new
      end

      def transform_raw_data!
        @raw_data.rewind

        @raw_data.each_line do |line|
          line_parts = line.split(':')

          case line_parts.count
            when 2
              @paths[Regexp.new(line_parts[0])] = line_parts[1]
            when 1
              @paths[Regexp.new(line_parts[0])] = false
            else
              raise "TCTP discovery information invalid (#{line})"
          end
        end
      end
    end
  end
end