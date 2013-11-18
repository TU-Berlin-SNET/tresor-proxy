require_relative 'connection'
require_relative 'logging'
require_relative 'connection_pool'

require 'logger'

module Tresor
  class TresorProxy
    @@logger = Logger.new(STDOUT)

    attr :host
    attr :port

    attr_accessor :is_tctp_client
    attr_accessor :is_tctp_server
    attr_accessor :reverse_mappings
    attr_accessor :connection_pool
    attr_accessor :halec_registry
    attr_accessor :name

    def initialize(host, port, name = "TRESOR Proxy")
      @host = host
      @port = port
      @name = name
      @connection_pool = ConnectionPool.new(self)
      @halec_registry = TCTP::HALECRegistry.new
    end

    def start
      begin
        EM.epoll
        EM.run do
          trap("TERM") { stop }
          trap("INT")  { stop }

          EventMachine.error_handler do |e|
            log.warn { "Error in event loop callback: #{e} #{e.message}" }
          end

          server = EventMachine::start_server(@host, @port, Tresor::Connection, self)

          log.info { "#{@name} started on #{@host}:#{@port}" }

          #if(log.level == Logger::DEBUG)
          #  EventMachine.add_periodic_timer(5) do
          #    free_connections_number = Tresor::ConnectionPool.instance_variable_get(:@free_backends).values.collect{|v| v.size}.reduce :+
          #
          #    log.debug ('ConnectionPool') {"#{free_connections_number} reusable connections."}
          #  end
          #end
        end
      rescue Exception => e
        log.fatal { "Error in TRESOR Proxy: #{e}" }
        log.fatal { e.backtrace }
      end
    end

    def stop
      log.info { "Terminating ProxyServer" }
      EventMachine.stop
    end

    def log
      @@logger
    end
  end
end