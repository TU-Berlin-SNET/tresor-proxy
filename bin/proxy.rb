$LOAD_PATH << File.realpath(File.join(File.dirname(File.realpath(__FILE__)), '..', 'lib'))
require 'tresor'

require 'eventmachine'
require 'slop'
require 'logger'
require 'yaml'

opts = Slop.parse(ARGV, :help => true) do
  banner 'Usage: proxy.rb [options]'

  on 'b=', 'broker', 'The URL of the TRESOR broker'
  on 'i=', 'ip', 'The ip address to bind to (default: all)'
  on 'p=', 'port', 'The port number (default: 80)'
  on 'n=', 'hostname', 'The HTTP hostname of the proxy (default: proxy.local)'
  on 'P=', 'threadpool', 'The Eventmachine thread pool size (default: 20)'
  on 't', 'trace', 'Enable tracing'
  on 'l=', 'loglevel', 'Specify log level (FATAL, ERROR, WARN, INFO, DEBUG - default INFO)'
  on 'logfile=', 'Specify log file'
  on 'logserver=', 'Specify remote logstash server uri, e.g., tcp://example.org:12345'
  on 'C', 'tctp_client', 'Enable TCTP client'
  on 'S', 'tctp_server', 'Enable TCTP server'
  on 'tls', 'Enable TLS'
  on 'tls_key=', 'Path to TLS key'
  on 'tls_crt=', 'Path to TLS server certificate'
  on 'reverse=', 'Load reverse proxy settings from YAML file'
  on 'raw_output', 'Output RAW data on console'
  on 'sso', 'Perform claims based authentication'
  on 'xacml', 'Perform XACML'
  on 'pdpurl=', 'The PDP URL'
  on 'fpurl=', 'The SSO federation provider URL'
  on 'hrurl=', 'The SSO home realm URL'
end

EventMachine.threadpool_size = opts[:threadpool] || 20

proxy = Tresor::Proxy::TresorProxy.new(opts[:ip] || '0.0.0.0', opts[:hostname] || 'proxy.local', opts[:port] || '80', 'TRESOR Proxy', opts[:tls] || false, opts[:tls_key], opts[:tls_crt])

proxy.log.level = Logger.const_get(opts[:loglevel] || 'INFO')
proxy.logserver = opts[:logserver]

proxy.is_tctp_client = opts[:tctp_client]
proxy.is_tctp_server = opts[:tctp_server]
proxy.is_sso_enabled = opts[:sso]
proxy.is_xacml_enabled = opts[:xacml]

proxy.xacml_pdp_rest_url = opts[:pdpurl]
proxy.fpurl = opts[:fpurl]
proxy.hrurl = opts[:hrurl]
proxy.output_raw_data = opts[:raw_output]
proxy.tresor_broker_url = opts[:broker]

if opts[:reverse]
  mappings = YAML::load_file(File.join(Dir.pwd, opts[:reverse]))

  proxy.reverse_mappings = mappings
end

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

at_exit do
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
end

puts 'Press any key to exit'

input = $stdin.gets

if input
  proxy.stop
else
  sleep
end