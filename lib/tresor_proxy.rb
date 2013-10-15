require_relative 'connection'

module Tresor
  class TresorProxy
    attr :host
    attr :port

    def initialize(host, port)
      @host = host
      @port = port
    end

    def start
      begin
        EM.epoll
        EM.run do
          trap("TERM") { stop }
          trap("INT")  { stop }

          EM.error_handler do |e|
            puts "Error in event loop callback: #{e} #{e.message}"
          end

          EventMachine::start_server(@host, @port, Tresor::Connection)

          puts "TRESOR Proxy started on #{@host}:#{@port}"
        end
      rescue Exception => e
        puts "Error in TRESOR Proxy: #{e}"
      end
    end

    def stop
      puts "Terminating ProxyServer"
      EventMachine.stop
    end
  end
end