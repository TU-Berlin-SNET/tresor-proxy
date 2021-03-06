require 'nokogiri'
require 'net/http'
require 'erb'

module Tresor
  module Frontend
    class XACML::DenyIfNotAuthorizedHandler < FrontendHandler
      class << self
        class << self
          include Tresor::Frontend::CommunicatesWith
        end

        communicates_with :pdp, :xacml_pdp_rest_url
        communicates_with :broker, :tresor_broker_url

        def xacml_request_template
          @xacml_request_template ||= ERB.new(File.read(File.join(__dir__, 'xacml_request.erb')))
        end

        def get_service_uuid(connection)
          begin
            service_name = connection.request.service_name

            connection.request.additional_headers_to_relay << {'TRESOR-Broker-Requested-Name' => service_name}

            broker_url = URI(connection.proxy.tresor_broker_url)

            http_request = Net::HTTP::Get.new("/service_uuid/#{service_name}")
            http_request['Host'] = "#{broker_url.host}:#{broker_url.port}"

            if(broker_url.userinfo)
              user, pw = broker_url.userinfo.split(':')
              http_request.basic_auth(user, pw)
            end

            http_response = communicate_with_broker(connection) do |http|
              http.request(http_request)
            end

            connection.request.additional_headers_to_relay << {'TRESOR-Broker-Response' => http_response.body.gsub("\n", '')}

            if(http_response.code == '200')
              service_uuid = http_response.body

              connection.request.additional_headers_to_send << {'TRESOR-Service-UUID' => service_uuid}

              return service_uuid
            else
              return 'unknown'
            end
          rescue Exception => e
            connection.request.additional_headers_to_relay << {'TRESOR-Broker-Exception' => "#{e.to_s}|#{e.backtrace.join(',')}"}

            return 'unknown'
          end
        end

        def authorized?(connection)
          begin
            request = connection.request

            subject_id = request.subject_id
            tresor_organization_uuid = request.subject_organization_uuid
            attributes = request.subject_attributes
            service_uuid = get_service_uuid(connection)
            uri = request.request_url.to_s
            http_method = request.http_method.downcase

            xacml_request = xacml_request_template.result(binding)

            request.additional_headers_to_relay << {'TRESOR-XACML-Request' => xacml_request.gsub("\n", '')}

            pdp_uri = URI(connection.proxy.xacml_pdp_rest_url)

            http_request = Net::HTTP::Post.new (pdp_uri.path == '' ? '/' : pdp_uri.path)
            http_request['Host'] = "#{pdp_uri.host}:#{pdp_uri.port}"
            http_request['Accept'] = 'application/xacml+xml'
            http_request['Content-Type'] = 'application/xacml+xml'
            http_request.body = xacml_request

            http_response = communicate_with_pdp(connection) do |http|
              http_response = http.request(http_request)
            end

            if(http_response.code == '200')
              begin
                request.additional_headers_to_relay << {'TRESOR-XACML-Response' => http_response.body}

                parsed_response = Nokogiri::XML(http_response.body)

                decision = parsed_response.xpath('/x:Response/x:Result/x:Decision/text()', 'x' => 'urn:oasis:names:tc:xacml:3.0:core:schema:wd-17').to_s

                request.additional_headers_to_relay << {'TRESOR-XACML-Decision' => decision}

                if decision.eql? 'Indeterminate'
                  missing_attributes = parsed_response.xpath('/x:Response/x:Result/x:Status/x:StatusDetail/x:MissingAttributeDetail/@AttributeId', 'x' => 'urn:oasis:names:tc:xacml:3.0:core:schema:wd-17')

                  missing_attributes.each do |attribute|
                    unless attribute.to_s.blank?
                      request.additional_headers_to_relay << {'TRESOR-XACML-Missing-Attribute' => attribute.to_s}
                    end
                  end
                end

                return decision.eql? 'Permit'
              rescue Exception => e
                request.additional_headers_to_relay << {'TRESOR-XACML-Error' => e.to_s}

                @error = :xacml_error

                return false
              end
            else
              request.additional_headers_to_relay << {'TRESOR-XACML-HTTP-Error' => http_response.body.gsub(/\r/,"").gsub(/\n/,"")}

              @error = :http_error

              return false
            end
          rescue Exception => e
            request.additional_headers_to_relay << {'TRESOR-XACML-Exception' => "#{e.to_s}|#{e.backtrace.join(',')}"}

            return false
          end
        end

        # @param [Tresor::Proxy::Connection] connection
        def can_handle?(connection)
          connection.proxy.is_xacml_enabled &&
          connection.request.http_relay? &&
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
        http_status = indeterminate_response? ? '307 Temporary Redirect' : '403 Forbidden'

        send_response_message(http_status)
      end

      def send_response_message(http_status)
        connection.send_data "HTTP/1.1 #{http_status}\r\n"
        connection.send_data "Host: #{connection.proxy.hostname}\r\n"
        connection.send_data "Content-Type: text/html; charset=UTF-8\r\n"

        connection.relay_additional_headers

        message = "<!doctype html><html><head/><body>#{build_message}</body>"

        connection.send_data "Content-Length: #{message.length}\r\n\r\n"
        connection.send_data message
      end

      def build_message
        request = connection.request

        request.additional_headers_to_relay.each do |hash|
          hash.each do |key, value|
            case key
              when 'TRESOR-XACML-Error'
                return "Error while processing XACML message\r\n#{value}"
              when 'TRESOR-XACML-HTTP-Error'
                return "Error while communicating with PDP\r\n#{value}"
              when 'TRESOR-XACML-Exception'
                return "General error in XACML module:\r\n#{value}"
              when 'TRESOR-XACML-Missing-Attribute'
                sso_redirect_url = get_sso_redirect_url(value)

                return "<p>Missing Attribute #{value}</p><p>Please authenticate: <a href='#{sso_redirect_url}'>here</a></p>"
            end
          end
        end

        #TODO Give more specific error
        return 'Forbidden'
      end

      def indeterminate_response?
        connection.request.additional_headers_to_relay_hash['TRESOR-XACML-Decision'].eql? 'Indeterminate'
      end

      def get_sso_redirect_url(attribute)
        ::Tresor::Frontend::ClaimSSO::RedirectToSSOFrontendHandler.build_redirect_url(connection, 'http://tresor.snet.tu-berlin.de/secure')
      end
    end
  end
end
