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
      EM.epoll
      EM.run do
        trap("TERM") { stop }
        trap("INT")  { stop }

        EventMachine::start_server(@host, @port, Tresor::Connection)

        puts "TRESOR Proxy started on #{@host}:#{@port}"
      end
    end

    def stop
      puts "Terminating ProxyServer"
      EventMachine.stop
    end
  end
end