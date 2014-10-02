require 'memoist'

module Tresor::Proxy
  # This class is used to represent an HTTP request to the TRESOR proxy
  class Request
    class << self
      include Tresor::Frontend::CommunicatesWith
    end

    extend Memoist

    communicates_with :broker, :tresor_broker_url

    # The client connection
    # @return [Tresor::Proxy::Connection] The connection
    attr :connection

    # The headers the client sent
    # @return [Hash]
    # @!attr [r] client_headers
    attr :client_headers

    # Additional headers, which are to be relayed to the client.
    # @!attr [rw] additional_headers_to_relay
    # @return [Array[Hash]] The additional headers
    attr_accessor :additional_headers_to_relay

    # Additional headers, which are to be sent to the upstream
    # server.
    # @!attr [rw] additional_headers_to_send
    # @return [Array[Hash]] The additional headers
    attr_accessor :additional_headers_to_send

    def initialize(connection, http_parser)
      @connection = connection
      @http_parser = http_parser
      @client_headers = @http_parser.headers

      @additional_headers_to_relay = []
      @additional_headers_to_send = []

      add_forward_headers
      add_tresor_headers

      set_sso_cookie
    end

    # The HTTP method, e.g., "GET", "POST", ...
    # @return [String] The HTTP method
    def http_method
      @http_parser.http_method
    end

    # The client-requested HTTP host
    # @return [String] The client-requested HTTP host
    def requested_http_host
      @client_headers['Host']
    end

    # The HTTP request URL as-is
    # @return [String]
    def requested_http_request_url
      @http_parser.request_url
    end

    # The reverse URL to the client-requested HTTP host,
    # e.g. "Host: example.com" => "http://www.reverse-example.com"
    #
    # @return [URI] The reverse url
    def reverse_url
      return URI(proxy.reverse_mappings[requested_http_host]) if proxy.reverse_mappings[requested_http_host]

      if proxy.is_sso_enabled && sso_session.present? && proxy.tresor_broker_url.present?
        service_name = requested_http_host.partition('.').first

        broker_url = URI(proxy.tresor_broker_url)

        http_request = Net::HTTP::Get.new("/clients/#{sso_session.tresor_organization_uuid}/endpoint_urls/#{service_name}")
        http_request['Host'] = "#{broker_url.host}:#{broker_url.port}"

        if broker_url.userinfo
          user, pw = broker_url.userinfo.split(':')
          http_request.basic_auth(user, pw)
        end

        http_response = communicate_with_broker(self) do |http|
          http.request(http_request)
        end

        if http_response.code == '200'
          return URI(http_response.body)
        end
      end

      nil
    end

    # The effective request URL, i.e., the URL which the user agent used
    # to connect to this proxy
    # @return [URI] The effective request URL
    def effective_request_url
      if http_forward?
        request_url.dup
      else
        scheme = connection.proxy.scheme
        host = requested_http_host
        request_url = @http_parser.request_url

        URI("#{scheme}://#{host}#{request_url}")
      end
    end

    # The effective backend_url, i.e., the forward or reverse host plus
    # the path and query string.
    # @return [URI] The backend host
    def effective_backend_url
      if http_forward?
        request_url.dup
      elsif http_reverse?
        effective_backend_url = reverse_url.dup

        effective_backend_url.path = request_url.path
        effective_backend_url.query = request_url.query
        effective_backend_url
      else
        nil
      end
    end

    # The HTTP host header, which should be sent to the backend
    # @return [String] The http host
    def effective_backend_host
      effective_backend_url.to_s.match(/https?:\/\/(.+?)(\/.*)/)[1]
    end

    # The effective backend scheme + authority.
    # e.g. "http://www.example.com" (effective backend URL without path,
    # query and fragment)
    def effective_backend_scheme_authority
      if effective_backend_url
        scheme_authority = effective_backend_url.dup
        scheme_authority.path, scheme_authority.query, scheme_authority.fragment = "", nil, nil
        scheme_authority
      else
        nil
      end
    end

    # Returns the parsed request URL. Contains the path and query string and
    # additionally a host on forward requests.
    # @return [URI::HTTP]
    def request_url
      parsed_request_url = URI.parse(requested_http_request_url)
      parsed_request_url.path = '/' if parsed_request_url.path.eql?('')
      parsed_request_url
    end

    # The request is an HTTP forward request if the request_url contains a
    # host.
    # @return [Boolean]
    def http_forward?
      request_url.host.present?
    end

    # The request is a reverse request, if there is a reverse URL
    # @return [Boolean]
    def http_reverse?
      reverse_url.present?
    end

    # The request is for the proxy as an origin server.
    # @return [Boolean]
    def http_origin?
      requested_http_host.eql?("#{@connection.proxy.hostname}:#{@connection.proxy.port}".gsub(/\:(80|443)\Z/, ''))
    end

    # The request should be relayed to a backend server.
    # @return [Boolean]
    def http_relay?
      http_forward? || http_reverse?
    end

    # Cookies contained in the request
    # @return [Hash] Cookies as Hash
    def cookies
      http_cookie_header = @http_parser.headers['Cookie']

      return {} unless http_cookie_header.present?

      begin
        Hash[http_cookie_header.split(';').map{|c| c.strip.split('=', 2)}]
      rescue Exception
        {}
      end
    end

    # The variables contained in the query part of the request URL
    # @return [Hash{String => String}]
    def query_vars
      http_query = request_url.query

      return {} unless http_query.present?

      begin
        Hash[http_query.split('&').map{|q| q.split('=')}]
      rescue Exception
        {}
      end
    end

    def chunked?
      @client_headers['Transfer-Encoding'].eql?('chunked')
    end

    # Gets the authorized subject ID
    # @return [String] The subject ID
    def subject_id
      sso_session ? sso_session.name_id : nil
    end

    def subject_organization
      sso_session ? sso_session.organization : nil
    end

    def subject_organization_uuid
      sso_session ? sso_session.tresor_organization_uuid : nil
    end

    # Gets the attributes of the authorized subject
    # @return [Hash] The attributes
    def subject_attributes
      sso_session ? sso_session.attributes_hash : {}
    end

    # Gets the SSO id, either from cookie or from query string
    # @return [String] The SSO id
    def sso_id
      query_vars['tresor_sso_id'] || cookies['tresor_sso_id']
    end

    # Gets the security token of the authorized subject
    # @return [ClaimSSOSecurityToken] The security token
    def sso_session
      if sso_id
        @connection.proxy.sso_sessions[sso_id]
      else
        nil
      end
    end

    # The service name is the part of the requested hostname
    # which comes before the first dot.
    # @return [String]
    def service_name
      requested_http_host[/(.+?)(?=\.)/]
    end

    memoize :effective_request_url, :reverse_url, :effective_backend_url, :request_url, :http_forward?, :http_reverse?, :http_origin?, :http_relay?, :cookies, :query_vars

    def proxy
      @connection.proxy
    end

    private
      def add_forward_headers
        if http_reverse?
          @additional_headers_to_send << {'X-Forwarded-Host' => requested_http_host}
        end
      end

      def set_sso_cookie
        if connection.proxy.is_sso_enabled && query_vars['tresor_sso_id'].present?
          # If both session ids (cookie and query vars) are not the same
          if query_vars['tresor_sso_id'] != cookies['tresor_sso_id']
            session_from_cookies = @connection.proxy.sso_sessions[cookies['tresor_sso_id']]
            session_from_query_vars = @connection.proxy.sso_sessions[query_vars['tresor_sso_id']]

            if session_from_cookies.blank?
              # If there was no session id in the cookies, set a cookie
              @additional_headers_to_relay << {'Set-Cookie' => "tresor_sso_id=#{sso_id}; path=/"}
            else
              if session_from_query_vars.blank?
                # If there is a valid session id in the cookies, but an invalid in the query vars
                # delete the invalid session id from the query vars
                query_vars.delete 'tresor_sso_id'
              end
            end
          end
        end
      end

      def add_tresor_headers
        if(sso_session)
          @additional_headers_to_send << {"TRESOR-Identity" => subject_id}
          @additional_headers_to_send << {"TRESOR-Organization" => subject_organization} if subject_organization
          @additional_headers_to_send << {"TRESOR-Organization-UUID" => subject_organization_uuid} if subject_organization_uuid

          subject_attributes.each do |attribute, values|
            values.each do |value|
              @additional_headers_to_send << {"TRESOR-Attribute" => "#{attribute} #{value}"}
            end
          end
        end
      end
  end
end