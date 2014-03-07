require_relative 'spec_helper'
require_relative 'test_server'

require 'webrick'
require 'thin'
require 'net/http'
require 'uri'
require 'rack-tctp'

describe 'A tctp client proxy' do
  before(:all) do
    @proxy = Tresor::Proxy::TresorProxy.new '127.0.0.1', '43213', 'TCTP client proxy'

    @proxy.is_tctp_client = true

    CLIENT_PROXY_TEST_SERVER = Tresor::TestServer.new
    @test_server = CLIENT_PROXY_TEST_SERVER

    @rack_stack = Rack::Builder.new do
      use Rack::TCTP

      run CLIENT_PROXY_TEST_SERVER
    end

    @webrick_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43214})
    @webrick_server.mount '/', Rack::Handler::WEBrick, @rack_stack.to_app

    Thread.new do @proxy.start end
    Thread.new do @webrick_server.start end

    until @proxy.started do sleep 0.1 end
    until @webrick_server.status.eql? :Running do sleep 0.1 end
  end

  after(:all) do
    @proxy.stop
    @webrick_server.stop

    while @proxy.started do sleep 0.1 end
    until @webrick_server.status.eql? :Stop do sleep 0.1 end
  end

  def proxy_uri
    URI.parse('http://127.0.0.1:43213')
  end

  def request_uri
    'http://127.0.0.1:43214'
  end

  it_behaves_like 'a TRESOR proxy' do
    def after_expectation
      expect(@proxy.halec_registry.instance_variable_get(:@halecs)['/halecs'].count).to be 1
    end

    let :after_post_expectation do
      Proc.new { after_expectation }
    end

    let :after_get_expectation do
      Proc.new { after_expectation }
    end
  end
end