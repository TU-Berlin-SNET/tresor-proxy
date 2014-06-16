require 'nokogiri'
require 'net/http'
require 'erb'

module Tresor
  module Frontend
    class XACML::DenyIfNotAuthorizedHandler < FrontendHandler
      class << self
        def xacml_request_template
          @xacml_request_template ||= ERB.new(File.read(File.join(__dir__, 'xacml_request.erb')))
        end

        def get_http_to_pdp(connection)
          http = connection.proxy.instance_variable_get(:@pdp_http)

          unless http
            pdp_uri = URI(connection.proxy.xacml_pdp_rest_url)

            http = Net::HTTP.new(pdp_uri.host, pdp_uri.port)

            connection.proxy.instance_variable_set(:@pdp_http, http)
          end

          http
        end

        def http_to_pdp_mutex(connection)
          mutex = connection.proxy.instance_variable_get(:@pdp_http_mutex)

          unless mutex
            mutex = Mutex.new

            connection.proxy.instance_variable_set(:@pdp_http_mutex, mutex)
          end

          mutex
        end

        def authorized?(connection)
          subject_id = connection.subject_id
          attributes = connection.subject_attributes
          uri = connection.parsed_request_uri.to_s
          http_method = connection.http_parser.http_method.downcase

          xacml_request = xacml_request_template.result(binding)

          connection.additional_headers_to_relay['TRESOR-XACML-Request'] = xacml_request.gsub("\n", '')

          http = get_http_to_pdp(connection)

          http_response = ''

          http_to_pdp_mutex(connection).synchronize do
            pdp_uri = URI(connection.proxy.xacml_pdp_rest_url)

            http_request = Net::HTTP::Post.new (pdp_uri.path == '' ? '/' : pdp_uri.path)
            http_request['Host'] = "#{pdp_uri.host}:#{pdp_uri.port}"
            http_request['Accept'] = 'application/xacml+xml'
            http_request['Content-Type'] = 'application/xacml+xml'
            http_request.body = xacml_request

            http_response = http.request(http_request)
          end

          if(http_response.code == '200')
            begin
              connection.additional_headers_to_relay['TRESOR-XACML-Response'] = http_response.body

              parsed_response = Nokogiri::XML(http_response.body)

              @decision = parsed_response.xpath('/x:Response/x:Result/x:Decision/text()', 'x' => 'urn:oasis:names:tc:xacml:3.0:core:schema:wd-17').to_s

              connection.additional_headers_to_relay['TRESOR-XACML-Decision'] = @decision

              @decision.eql? 'Permit'
            rescue Exception => e
              connection.additional_headers_to_relay['TRESOR-XACML-Error'] = e.to_s
            end
          else
            connection.additional_headers_to_relay['TRESOR-XACML-HTTP-Error'] = http_response.body.gsub(/\r/,"").gsub(/\n/,"")
          end
        end

        # @param [Tresor::Proxy::Connection] connection
        def can_handle?(connection)
          connection.proxy.is_xacml_enabled &&
          !connection.http_parser.headers['Host'].start_with?(connection.proxy.hostname) &&
          !authorized?(connection)
        end
      end

      # @param [Tresor::Proxy::Connection] connection
      def initialize(connection)
        super(connection)
      end

      def on_body(chunk)

      end

      def on_message_complete
        connection.send_data "HTTP/1.1 403 Forbidden\r\n"
        connection.send_data "Host: #{connection.proxy.hostname}\r\n"

        connection.additional_headers_to_relay.each do |header, value|
          connection.send_data "#{header}: #{value}\r\n"
        end

        connection.send_data "Content-Length: #{build_forbidden_message.length}\r\n\r\n"
        connection.send_data build_forbidden_message
      end

      def build_forbidden_message
        'Forbidden'
      end
    end
  end
end
