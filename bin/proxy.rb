require_relative '../lib/tresor_proxy'

require 'eventmachine'
require 'slop'
require 'logger'

opts = Slop.parse do
  banner 'Usage: proxy.rb [options]'

  on 'i=', 'ip', 'The ip address to bind to (default: all)'
  on 'p=', 'port', 'The port number (default: 80)'
  on 's=', 'threadpool', 'The Eventmachine thread pool size (default: 20)'
  on 't', 'trace', 'Enable tracing'
  on 'l=', 'loglevel', 'Specify log level (FATAL, ERROR, WARN, INFO, DEBUG - default INFO)'
  on 'c', 'tctp_client', 'Enable TCTP client forwarding proxy'
  on 'r', 'tctp_server', 'Enable TCTP server reverse proxy'
end

EventMachine.threadpool_size = opts[:threadpool] || 20

logger = Logger.new(STDOUT)
logger.level = Logger.const_get(opts[:loglevel] || 'INFO')

Tresor::TresorProxy.class_variable_set(:@@logger, logger)

proxy = Tresor::TresorProxy.new(opts[:ip] || '0.0.0.0', opts[:port] || '80')

proxy.is_tctp_client = opts[:tctp_client]
proxy.is_tctp_server = opts[:tctp_server]

require 'ruby-prof' if (opts.trace? && RUBY_PLATFORM != 'java')

Thread.new do
  if opts.trace?
    if RUBY_PLATFORM != 'java' then
      RubyProf.start
    else
      JRuby::Profiler.start
    end
  end

  proxy.start
end

puts 'Press any key to exit'

$stdin.gets.chomp!

proxy.stop

if opts.trace?
  if RUBY_PLATFORM != 'java' then
    result = RubyProf.stop

    printer = RubyProf::CallTreePrinter.new(result)
    File.open('profile-results', 'w') do |f|
      printer.print(f)
    end
  else
    result = JRuby::Profiler.stop

    printer = JRuby::Profiler::GraphPrinter.new(result)
    File.open('profile-results', 'w') do |f|
      printer.printProfile(f)
    end
  end
end