require 'nokogiri'

module Tresor
  module Frontend
    module ClaimSSO
      class RedirectToSSOFrontendHandler < Tresor::Frontend::FrontendHandler
        class << self
          # @param [Tresor::Proxy::Connection] connection
          def can_handle?(connection)
            connection.proxy.is_sso_enabled &&
            !connection.http_parser.headers['Host'].start_with?(connection.proxy.hostname) &&
            connection.sso_session == nil
          end
        end

        # @param [Tresor::Proxy::Connection] connection
        def initialize(connection)
          super(connection)
        end

        def on_body(chunk)

        end

        def on_message_complete
          connection.send_data "HTTP/1.1 302 Found\r\n"
          connection.send_data "Host: #{connection.http_parser.headers['Host']}\r\n"
          # TODO Send wct
          connection.send_data "Content-Length: #{build_http_response.length}\r\n"
          connection.send_data "Location: #{build_redirect_url}\r\n\r\n"
          connection.send_data build_http_response

          log.debug (log_key) { "Sent redirect to federation provider" }
        end

        def build_redirect_url
          "#{connection.proxy.fpurl}/?wa=wsignin1.0&wtrealm=#{build_wtrealm_url}&whr=#{build_whr_url}"
        end

        def build_wtrealm_url
          wdycf_url = "http://#{connection.http_parser.headers['Host']}#{URI(connection.http_parser.request_url).path}"

          return URI.encode_www_form_component("http://#{connection.proxy.hostname}:#{connection.proxy.port}/?wdycf_url=#{wdycf_url}")
        end

        def build_whr_url
          URI.encode_www_form_component(connection.proxy.hrurl)
        end

        def build_http_response
          "<http><head></head><body><p>Please authenticate:</p><p><a href='#{build_redirect_url}'>#{build_redirect_url}</a></p></body></html>"
        end
      end
    end
  end
end