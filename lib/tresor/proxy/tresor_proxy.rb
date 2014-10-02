require 'logger'

module Tresor::Proxy
  class TresorProxy
    @@logger = Logger.new(STDOUT)

    # The IP this proxy should listen to
    # @return [Integer]
    # @!attr [r] ip
    attr :ip

    # The primary HTTP hostname of this proxy
    # @return [String]
    # @!attr [r] hostname
    attr :hostname

    # The port, on which this proxy should listen
    # @return [Integer]
    # @!attr [r] port
    attr :port

    # Is TLS enabled
    # @return [Boolean]
    # @!attr [r] tls
    attr :tls

    attr :tls_key
    attr :tls_crt

    # Does this proxy encrypt messages upstream?
    # !@attr [rw] is_tctp_client
    # @return [Boolean]
    attr_accessor :is_tctp_client

    # Does this proxy decrypt incoming messages?
    # !@attr [rw] is_tctp_server
    # @return [Boolean]
    attr_accessor :is_tctp_server

    # Does the proxy perform Single-Sign-On?
    # !@attr [rw] is_sso_enabled
    # @return [Boolean]
    attr_accessor :is_sso_enabled

    # Does the proxy perform XACML authorization?
    # !@attr [rw] is_xacml_enabled
    # @return [Boolean]
    attr_accessor :is_xacml_enabled

    # The XACML PDP Rest URL
    # !@attr [rw] xacml_pdp_rest_url
    # @return [String]
    attr_accessor :xacml_pdp_rest_url

    # Does this proxy output raw data on the console?
    # !@attr [rw] output_raw_data
    # @return [Boolean]
    attr_accessor :output_raw_data

    # Mapping from URLs to reverse hosts, e.g. `{'google.local' => 'http://www.google.com'}`
    # !@attr [rw] reverse_mappings
    # @return [Hash{String => String}] Mappings for reverse hosts.
    attr_accessor :reverse_mappings

    # SSO Federation Provider URL
    # !@attr [rw] fpurl
    # @return [String]
    attr_accessor :fpurl

    # SSO Home Realm URL
    # !@attr [rw] hrurl
    # @return [String]
    attr_accessor :hrurl

    # The SSO sessions.
    # !@attr [rw] sso_sessions
    # @return [Hash[String => String]] A mapping of SSO session ID to ClaimSSOSecurityToken
    attr_accessor :sso_sessions

    # The proxy connection pool
    # !@attr [r] connection_pool
    # @return [Tresor::Proxy::ConnectionPool]
    attr :connection_pool
    attr_accessor :halec_registry
    attr_accessor :name
    attr_accessor :started

    attr_accessor :tresor_broker_url

    ##
    # Proc for when the proxy is started.
    #
    # Contains a block, which sets +started+ to +true+.
    #
    # @!attribute [r] start_callback
    # @return [Proc]
    attr :start_proc

    ##
    # Proc for when the proxy is stopped.
    #
    # Contains a block, which sets +started+ to +false+.
    #
    # @!attribute [r] stop_callback
    # @return [Proc]
    attr :stop_proc

    def initialize(ip, hostname, port, name = "TRESOR Proxy", tls = false, tls_key = nil, tls_crt = nil)
      @ip = ip
      @hostname = hostname
      @port = port
      @name = name
      @tls = tls
      @tls_key = tls_key
      @tls_crt = tls_crt
      @connection_pool = ConnectionPool.new(self)
      @halec_registry = Tresor::TCTP::HALECRegistry.new
      @reverse_mappings = {}
      @sso_sessions = {}

      @start_proc = proc do
        @started = true
      end

      @stop_proc = proc do
        @started = false
      end
    end

    def start
      begin
        EM.epoll
        EM.run do
          trap("KILL") { stop }
          trap("TERM") { stop }
          trap("INT")  { stop }

          EventMachine.error_handler do |e|
            log.warn { "Error in event loop callback: #{e} #{e.message}" }

            e.backtrace.each do |bt|
              log.warn bt
            end
          end

          EventMachine::start_server(@ip, @port, Connection, self)

          log.info { "#{@name} started on #{@ip}:#{@port}" }

          @start_proc.call
        end
      rescue Exception => e
        log.fatal { "Error in TRESOR Proxy: #{e}" }
        log.fatal { e.backtrace }

        retry
      end
    end

    def stop
      EventMachine.stop_event_loop

      @stop_proc.call

      exit(0)
    end

    def scheme
      tls ? 'https' : 'http'
    end

    def log
      @@logger
    end

    class << self
      def logger
        @@logger
      end
    end
  end
end