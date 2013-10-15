require_relative '../lib/tresor_proxy'

require 'eventmachine'
require 'slop'

opts = Slop.parse do
  banner 'Usage: proxy.rb [options]'

  on 'i=', 'ip', 'The ip address to bind to (default: all)'
  on 'p=', 'port', 'The port number (default: 80)'
  on 't', 'trace', 'Enable tracing'
end

proxy = Tresor::TresorProxy.new(opts[:ip] || '0.0.0.0', opts[:port] || '80')

require 'ruby-prof' if opts.trace?

Thread.new do
  RubyProf.start if opts.trace?

  proxy.start
end

puts 'Press any key to exit'

$stdin.gets.chomp!

proxy.stop

if opts.trace?
  result = RubyProf.stop

  printer = RubyProf::CallTreePrinter.new(result)
  File.open('profile-results', 'w') do |f|
    printer.print(f)
  end
end