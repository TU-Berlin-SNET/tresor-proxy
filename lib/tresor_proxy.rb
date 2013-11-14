require_relative 'connection'
require_relative 'logging'
require_relative 'connection_pool'

module Tresor
  class TresorProxy
    attr :host
    attr :port

    attr_accessor :is_tctp_client
    attr_accessor :is_tctp_server
    attr_accessor :reverse_mappings
    attr_accessor :connection_pool
    attr_accessor :halec_registry

    def initialize(host, port)
      @host = host
      @port = port
      @connection_pool = ConnectionPool.new(self)
      @halec_registry = TCTP::HALECRegistry.new
    end

    def start
      begin
        EM.epoll
        EM.run do
          trap("TERM") { stop }
          trap("INT")  { stop }

          EM.error_handler do |e|
            log.warn { "Error in event loop callback: #{e} #{e.message}" }
            log.warn { e.backtrace }
          end

          EventMachine::start_server(@host, @port, Tresor::Connection) do |c|
            c.proxy = self
          end

          log.info { "TRESOR Proxy started on #{@host}:#{@port}" }

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