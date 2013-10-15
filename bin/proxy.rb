require_relative '../lib/tresor_proxy'

require 'eventmachine'
require 'ruby-prof'

EventMachine.threadpool_size = 8

proxy = Tresor::TresorProxy.new('127.0.0.1', '3001')

Thread.new do
  RubyProf.start

  proxy.start
end

readline

proxy.stop

result = RubyProf.stop

printer = RubyProf::CallTreePrinter.new(result)
File.open('profile-results', 'w') do |f|
  printer.print(f)
end