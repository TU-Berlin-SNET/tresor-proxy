require_relative 'connection'
require_relative 'logging'
require_relative 'connection_pool'

require 'fiber'
require 'em-synchrony'
require 'logger'

module Tresor
  class TresorProxy
    @@logger = Logger.new(STDOUT)

    attr :host
    attr :port

    # Does this proxy encrypt messages upstream?
    #
    # !@attr [rw] is_tctp_client
    # @return [Boolean] Does this proxy encrypt messages upstream?
    attr_accessor :is_tctp_client

    # Does this proxy decrypt incoming messages?
    #
    # !@attr [rw] is_tctp_server
    # @return [Boolean] Does this proxy decrypt incoming messages?
    attr_accessor :is_tctp_server

    attr_accessor :output_raw_data

    # Mapping from URLs to reverse hosts, e.g. `{'google.local' => 'http://www.google.com'}`
    #
    # !@attr [rw] reverse_mappings
    # @return [Hash{String => String}] Mappings for reverse hosts.
    attr_accessor :reverse_mappings


    attr_accessor :connection_pool
    attr_accessor :halec_registry
    attr_accessor :name
    attr_accessor :started

    ##
    # Callback for when the proxy is started.
    #
    # Contains a block, which sets +started+ to +true+.
    #
    # @!attribute [r] start_callback
    # @return [EventMachine::DefaultDeferrable]
    attr :start_callback

    ##
    # Callback for when the proxy is stopped.
    #
    # Contains a block, which sets +started+ to +false+.
    #
    # @!attribute [r] start_callback
    # @return [EventMachine::DefaultDeferrable]
    attr :stop_callback

    def initialize(host, port, name = "TRESOR Proxy")
      @host = host
      @port = port
      @name = name
      @connection_pool = ConnectionPool.new(self)
      @halec_registry = TCTP::HALECRegistry.new
      @reverse_mappings = {}

      @start_callback = EventMachine::DefaultDeferrable.new
      @start_callback.callback do
        @started = true
      end

      @stop_callback = EventMachine::DefaultDeferrable.new
      @stop_callback.callback do
        @started = false
      end
    end

    def start
      begin
        EM.epoll
        EM.synchrony do
          trap("TERM") { stop }
          trap("INT")  { stop }

          EventMachine.error_handler do |e|
            log.warn { "Error in event loop callback: #{e} #{e.message}" }

            e.backtrace.each do |bt|
              log.warn bt
            end
          end

          EventMachine::start_server(@host, @port, Tresor::Connection, self)

          log.info { "#{@name} started on #{@host}:#{@port}" }

          start_callback.succeed
        end
      rescue Exception => e
        log.fatal { "Error in TRESOR Proxy: #{e}" }
        log.fatal { e.backtrace }
      end
    end

    def stop
      log.info { "Terminating ProxyServer" }
      EventMachine.stop

      @stop_callback.succeed
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