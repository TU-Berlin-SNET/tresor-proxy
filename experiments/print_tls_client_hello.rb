require 'eventmachine'

class TLSClient < EventMachine::Connection
  def connection_completed
    start_tls
  end
end

Thread.new do
  EM.epoll
  EM.run do
    EM.connect '127.0.0.1', '60000', TLSClient
  end
end

server = TCPServer.new('127.0.0.1', 60000)
client_connection = server.accept
client_hello = client_connection.readpartial(16 * 1024)

puts client_hello