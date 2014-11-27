module Tresor
  module Frontend
    module ClaimSSO
      class ProcessSAMLResponseFrontendHandler < Tresor::Frontend::FrontendHandler
        class << self
          include Tresor::Frontend::CommunicatesWith
        end

        communicates_with :broker, :tresor_broker_url

        class << self
          # @param [Tresor::Proxy::Connection] connection
          def can_handle?(connection)
            connection.proxy.is_sso_enabled &&
            connection.request.http_origin? &&
            connection.request.http_method.eql?('POST') &&
            connection.request.query_vars['wdycf_url']
          end
        end

        def on_body(chunk)
          @sso_response ||= StringIO.new
          @sso_response.write chunk
        end

        def on_message_complete
          if @sso_response
            EM.defer do
              parsed_sso_response = Hash[URI.decode_www_form(@sso_response.string)]

              security_token = ClaimSSOSecurityToken.new(parsed_sso_response['wresult'])

              broker_url = URI(connection.proxy.tresor_broker_url)

              http_request = Net::HTTP::Get.new("/clients/tresor_organization_ids/#{security_token.organization}")
              http_request['Host'] = "#{broker_url.host}:#{broker_url.port}"

              if(broker_url.userinfo)
                user, pw = broker_url.userinfo.split(':')
                http_request.basic_auth(user, pw)
              end

              security_token.tresor_organization_uuid = begin
                http_response = communicate_with_broker(connection) do |http|
                  http.request(http_request)
                end

                if(http_response.code == '200')
                  http_response.body
                else
                  'unknown'
                end
              rescue Exception => e
                connection.additional_headers_to_relay['TRESOR-Broker-Exception'] = "#{e.to_s}|#{e.backtrace.join(',')}"

                'unknown'
              end

              new_id = SecureRandom.urlsafe_base64

              connection.proxy.sso_sessions[new_id] = security_token

              wdycf_url = build_wdycf_url(new_id)

              # Redirect to where-do-you-come-from-url
              EM.schedule do
                connection.send_data "HTTP/1.1 302 Found \r\n"
                connection.send_data "Host: #{connection.proxy.hostname}\r\n"
                connection.send_data "Content-Length: #{build_html_response(wdycf_url).length}\r\n"
                connection.send_data "Location: #{wdycf_url}\r\n\r\n"
                connection.send_data build_html_response(wdycf_url)
              end

              log_remote(Logger::INFO, {
                category: 'Authentication',
                message: "Successfully authenticated user #{security_token.name_id} for access to #{connection.request.query_vars['wdycf_url']}",
                'client-id' => security_token.tresor_organization_uuid,
                'subject-id' => security_token.name_id
              })
            end
          else
            connection.send_error_response Exception.new('SSO token missing')
          end
        end

        def build_wdycf_url(id)
          parsed_wdycf_url = URI(connection.request.query_vars['wdycf_url'])

          if parsed_wdycf_url.query.present?
            parsed_wdycf_url.query += "&tresor_sso_id=#{id}"
          else
            parsed_wdycf_url.query = "tresor_sso_id=#{id}"
          end

          parsed_wdycf_url.to_s
        end

        def build_html_response(url)
          "<http><head></head><body><p>Thank you for logging in.</p><p><a href='#{url}'>#{url}</a></p></body></html>"
        end
      end
    end
  end
end