require_relative 'spec_helper'

require_relative '../lib/tresor_proxy'
require_relative 'test_server'

require 'thin'
require 'net/http'
require 'uri'
require 'webrick'

describe 'A set of tctp proxies' do
  before(:all) do
    @first_proxy = Tresor::TresorProxy.new '127.0.0.1', '43210', 'First TCTP proxy'
    @second_proxy = Tresor::TresorProxy.new '127.0.0.1', '43211', 'Second TCTP proxy'

    @first_proxy.is_tctp_client = true

    @second_proxy.is_tctp_server = true
    @second_proxy.reverse_mappings = { '127.0.0.1' => 'http://127.0.0.1:43212' }

    @test_server = Tresor::TestServer.new

    TEST_SERVER = Tresor::TestServer.new
    @test_server = TEST_SERVER

    @rack_stack = Rack::Builder.new do
      run TEST_SERVER
    end

    @webrick_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43212})
    @webrick_server.mount '/', Rack::Handler::WEBrick, @rack_stack.to_app

    Thread.new do @first_proxy.start end
    Thread.new do @second_proxy.start end
    Thread.new do @webrick_server.start end

    until @first_proxy.started do end
    until @second_proxy.started do end
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

  it 'ignores bad halec URL' do
    pending
  end
end