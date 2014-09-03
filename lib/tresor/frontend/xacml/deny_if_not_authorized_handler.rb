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
            http.proxy_address = nil

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

        def get_http_to_broker(connection)
          http = connection.proxy.instance_variable_get(:@broker_http)

          unless http
            broker_uri = URI(connection.proxy.tresor_broker_url)

            http = Net::HTTP.new(broker_uri.host, broker_uri.port)
            http.proxy_address = nil

            connection.proxy.instance_variable_set(:@broker_http, http)
          end

          http
        end

        def http_to_broker_mutex(connection)
          mutex = connection.proxy.instance_variable_get(:@broker_http_mutex)

          unless mutex
            mutex = Mutex.new

            connection.proxy.instance_variable_set(:@broker_http_mutex, mutex)
          end

          mutex
        end

        def get_service_uuid(connection)
          begin
            service_name = connection.parsed_request_uri.respond_to?(:request_uri) ?
                connection.parsed_request_uri.hostname.partition('.').first : connection.host.partition('.').first

            http = get_http_to_broker(connection)

            http_to_broker_mutex(connection).synchronize do
              broker_url = URI(connection.proxy.tresor_broker_url)

              http_request = Net::HTTP::Get.new("/service_uuid/#{service_name}")
              http_request['Host'] = "#{broker_url.host}:#{broker_url.port}"

              if(broker_url.userinfo)
                user, pw = broker_url.userinfo.split(':')
                http_request.basic_auth(user, pw)
              end

              http_response = http.request(http_request)

              if(http_response.code == '200')
                return http_response.body
              else
                connection.additional_headers_to_relay['TRESOR-Broker-Response'] = http_response.body.gsub("\n", '')

                return 'unknown'
              end
            end
          rescue Exception => e
            connection.additional_headers_to_relay['TRESOR-Broker-Exception'] = "#{e.to_s}|#{e.backtrace.join(',')}"

            return 'unknown'
          end
        end

        def authorized?(connection)
          begin
            subject_id = connection.subject_id
            attributes = connection.subject_attributes
            service_uuid = get_service_uuid(connection)
            uri = connection.parsed_request_uri.respond_to?(:request_uri) ? connection.parsed_request_uri : connection.parsed_request_uri.to_s
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

                return @decision.eql? 'Permit'
              rescue Exception => e
                connection.additional_headers_to_relay['TRESOR-XACML-Error'] = e.to_s

                @error = :xacml_error

                return false
              end
            else
              connection.additional_headers_to_relay['TRESOR-XACML-HTTP-Error'] = http_response.body.gsub(/\r/,"").gsub(/\n/,"")

              @error = :http_error

              return false
            end
          rescue Exception => e
            connection.additional_headers_to_relay['TRESOR-XACML-Exception'] = "#{e.to_s}|#{e.backtrace.join(',')}"

            return false
          end
        end

        # @param [Tresor::Proxy::Connection] connection
        def can_handle?(connection)
          connection.proxy.is_xacml_enabled &&
          !connection.request_is_for_proxy &&
          !authorized?(connection)
        end
      end

      # @param [Tresor::Proxy::Connection] connection
      def initialize(connection)
        @error = false

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

        message = build_message

        connection.send_data "Content-Length: #{message.length}\r\n\r\n"
        connection.send_data message
      end

      def build_message
        if(connection.additional_headers_to_relay['TRESOR-XACML-Error'])
          "Error while processing XACML message\r\n#{connection.additional_headers_to_relay['TRESOR-XACML-Error']}"
        elsif(connection.additional_headers_to_relay['TRESOR-XACML-HTTP-Error'])
          "Error while communicating with PDP\r\n#{connection.additional_headers_to_relay['TRESOR-XACML-HTTP-Error']}"
        elsif(connection.additional_headers_to_relay['TRESOR-XACML-Exception'])
          "General error in XACML module:\r\n#{connection.additional_headers_to_relay['TRESOR-XACML-Exception']}"
        else
          'forbidden'
        end
      end
    end
  end
end
