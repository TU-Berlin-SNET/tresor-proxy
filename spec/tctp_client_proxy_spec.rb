require_relative 'spec_helper'

require_relative '../lib/tresor_proxy'
require_relative 'test_server'

require 'webrick'
require 'thin'
require 'net/http'
require 'uri'
require 'rack-tctp'

describe 'A tctp client proxy' do
  before(:all) do
    @proxy = Tresor::TresorProxy.new '127.0.0.1', '43210', 'TCTP client proxy'

    @proxy.is_tctp_client = true

    TEST_SERVER = Tresor::TestServer.new
    @test_server = TEST_SERVER

    @rack_stack = Rack::Builder.new do
      use Rack::TCTP

      run TEST_SERVER
    end

    @webrick_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43211})
    @webrick_server.mount '/', Rack::Handler::WEBrick, @rack_stack.to_app

    Thread.new do @proxy.start end
    Thread.new do @webrick_server.start end

    until @proxy.started do end
  end

  after(:all) do
    @proxy.stop
    @thin_server.stop
  end

  let :proxy_uri do
    URI.parse('http://127.0.0.1:43210')
  end

  let :request_uri do
    'http://127.0.0.1:43211'
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