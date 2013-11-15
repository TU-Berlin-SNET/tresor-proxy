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

Thread.new do
  local_proxy.start
end

Thread.new do
  remote_proxy.start
end

puts 'Press any key to exit'

$stdin.gets.chomp!