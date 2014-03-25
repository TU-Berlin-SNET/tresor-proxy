require_relative 'spec_helper'
require_relative 'test_server'

require 'webrick'
require 'thin'
require 'net/http'
require 'uri'
require 'faker'

describe 'A basic forward proxy' do
  before(:all) do
    @proxy = Tresor::Proxy::TresorProxy.new '127.0.0.1', 'proxy.local', '43208', 'Basic test proxy'

    BASIC_FORWARD_TEST_SERVER = Tresor::TestServer.new
    @test_server = BASIC_FORWARD_TEST_SERVER

    @rack_stack = Rack::Builder.new do
      run BASIC_FORWARD_TEST_SERVER
    end

    @webrick_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43209})
    @webrick_server.mount '/', Rack::Handler::WEBrick, @rack_stack.to_app

    Thread.new do @proxy.start end
    Thread.new do @webrick_server.start end
    until @proxy.started do Thread.pass end
    until @webrick_server.status.eql? :Running do sleep 0.1 end
  end

  after(:all) do
    @proxy.stop
    @thin_server.stop

    while @proxy.started do sleep 0.1 end
    until @webrick_server.status.eql? :Stop do sleep 0.1 end
  end

  let :proxy_uri do
    URI.parse('http://127.0.0.1:43208')
  end

  let :request_uri do
    'http://127.0.0.1:43209'
  end

  it 'can be started' do
    expect(@proxy.started).to be_true
  end

  it 'returns 502 error when trying to access a not configured reverse host' do
    proxy_uri = URI.parse('http://127.0.0.1:43208')
    test_server_uri = URI.parse('http://127.0.0.1:43209')

    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    request = Net::HTTP::Get.new(test_server_uri)

    response = http.request request

    expect(response.code).to eq '502'
  end

  it_behaves_like 'a TRESOR proxy' do
    def after_expectation

    end

    let :after_post_expectation do
      Proc.new { after_expectation }
    end

    let :after_get_expectation do
      Proc.new { after_expectation }
    end
  end
end