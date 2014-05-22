module Tresor
  module Frontend
    module ClaimSSO
      class ProcessSAMLResponseFrontendHandler < Tresor::Frontend::FrontendHandler
        class << self
          # @param [Tresor::Proxy::Connection] connection
          def can_handle?(connection)
            connection.proxy.is_sso_enabled &&
            connection.http_parser.headers['Host'].start_with?(connection.proxy.hostname) &&
            connection.http_parser.http_method.eql?('POST') &&
            connection.query_vars['wdycf_url']
          end
        end

        def on_body(chunk)
          @sso_response ||= StringIO.new
          @sso_response.write chunk
        end

        def on_message_complete
          if @sso_response
            parsed_sso_response = Hash[URI.decode_www_form(@sso_response.string)]

            security_token = ClaimSSOSecurityToken.new(parsed_sso_response['wresult'])
            new_id = SecureRandom.urlsafe_base64

            connection.proxy.sso_sessions[new_id] = security_token

            wdycf_url = build_wdycf_url(new_id)

            # Redirect to where-do-you-come-from-url
            connection.send_data "HTTP/1.1 302 Found \r\n"
            connection.send_data "Host: #{connection.proxy.hostname}\r\n"
            connection.send_data "Content-Length: #{build_html_response(wdycf_url).length}\r\n"
            connection.send_data "Location: #{build_wdycf_url(new_id)}\r\n\r\n"
            connection.send_data build_html_response(wdycf_url)
          else
            connection.send_error_response Exception.new('SSO token missing')
          end
        end

        def build_wdycf_url(id)
          "#{connection.query_vars['wdycf_url']}?tresor_sso_id=#{id}"
        end

        def build_html_response(url)
          "<http><head></head><body><p>Thank you for logging in.</p><p><a href='#{url}'>#{url}</a></p></body></html>"
        end
      end
    end
  end
end