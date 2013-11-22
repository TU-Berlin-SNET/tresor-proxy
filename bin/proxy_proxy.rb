require 'ruby-prof'
require 'eventmachine'

EventMachine.threadpool_size = 100

def trace_output(data)
  File.open('trace.bin', 'a') do |f|
    f << data
  end
end

TRACE = false

require_relative '../lib/tresor_proxy'

local_proxy = Tresor::TresorProxy.new('127.0.0.1', '12345', 'Local Proxy')
remote_proxy = Tresor::TresorProxy.new('127.0.0.1', '54321', 'Remote Proxy')

local_proxy.is_tctp_client = true
remote_proxy.is_tctp_server = true

local_proxy.reverse_mappings = {
    'app.local' => 'http://127.0.0.1:54321',
}

remote_proxy.reverse_mappings = {
    'app.local' => 'http://127.0.0.1:3000'
}

#local_proxy.log.level = Logger::DEBUG
#remote_proxy.log.level = Logger::DEBUG

local_proxy.log.level = Logger::WARN
remote_proxy.log.level = Logger::WARN

RubyProf.start if TRACE

Thread.new do
  local_proxy.start
end

Thread.new do
  remote_proxy.start
end

puts 'Press any key to exit'

$stdin.gets.chomp!

if TRACE
  result = RubyProf.stop

  printer = RubyProf::CallTreePrinter.new(result)
  File.open('profile-results', 'w') do |f|
    printer.print(f)
  end
end