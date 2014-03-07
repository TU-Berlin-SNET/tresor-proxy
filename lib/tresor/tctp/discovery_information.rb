module Tresor
  module TCTP
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