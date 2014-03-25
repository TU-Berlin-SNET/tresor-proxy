require_relative 'spec_helper'
require_relative 'test_server'

require 'thin'
require 'net/http'
require 'uri'
require 'webrick'

describe 'A set of tctp proxies' do
  before(:all) do
    puts "Before a set of tctp proxies"

    @first_proxy = Tresor::Proxy::TresorProxy.new '127.0.0.1', 'proxy.local', '43210', 'First TCTP proxy'
    @second_proxy = Tresor::Proxy::TresorProxy.new '127.0.0.1', 'proxy.local', '43211', 'Second TCTP proxy'

    @first_proxy.is_tctp_client = true

    @second_proxy.is_tctp_server = true
    @second_proxy.reverse_mappings = { '127.0.0.1' => 'http://127.0.0.1:43212' }

    @test_server = Tresor::TestServer.new

    PROXY_SET_TEST_SERVER = Tresor::TestServer.new
    @test_server = PROXY_SET_TEST_SERVER

    @rack_stack = Rack::Builder.new do
      run PROXY_SET_TEST_SERVER
    end

    @webrick_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43212})
    @webrick_server.mount '/', Rack::Handler::WEBrick, @rack_stack.to_app

    Thread.new do @first_proxy.start end
    Thread.new do @second_proxy.start end
    Thread.new do @webrick_server.start end

    until @first_proxy.started do sleep 0.1 end
    until @second_proxy.started do sleep 0.1 end
    until @webrick_server.status.eql? :Running do sleep 0.1 end
  end

  after(:all) do
    @first_proxy.stop
    @second_proxy.stop
    @webrick_server.stop

    while @first_proxy.started do sleep 0.1 end
    while @second_proxy.started do sleep 0.1 end
    until @webrick_server.status.eql? :Stop do sleep 0.1 end
  end

  def proxy_uri
    URI.parse('http://127.0.0.1:43210')
  end

  def request_uri
    'http://127.0.0.1:43211'
  end

  it_behaves_like 'a TRESOR proxy' do
    def shared_expectation
      Proc.new do
        expect(@first_proxy.halec_registry).not_to be_empty
        expect(@second_proxy.halec_registry).not_to be_empty
      end
    end

    let :after_get_expectation do
      shared_expectation
    end

    let :after_post_expectation do
      shared_expectation
    end
  end

  #it 'ignores bad halec URL' do
  #  pending
  #end
end