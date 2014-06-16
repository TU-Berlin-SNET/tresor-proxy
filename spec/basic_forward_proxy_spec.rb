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

    @thin_server = Thin::Server.new '127.0.0.1', 43209, @rack_stack.to_app

    Thread.new do @proxy.start end
    Thread.new do @thin_server.start end
    until @proxy.started do Thread.pass end
    until @thin_server.running? do Thread.pass end
  end

  after(:all) do
    @proxy.stop
    @thin_server.stop

    while @proxy.started do Thread.pass end
    while @thin_server.running? do Thread.pass end
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

  it 'does not allow CONNECT' do
    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    request = Net::HTTP::Connect.new('127.0.0.1:43209')

    request.body = test_body

    response = http.request request

    expect(response.code).to eq '405'
    expect(response.body.length).to eq 0
  end

  it 'can be accessed in parallel' do
    threadgroup = ThreadGroup.new

    finished = 0

    @test_server.current_post_body = test_body

    2.times do
      threadgroup.add(Thread.new do
        5.times do
          http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
          request = Net::HTTP::Post.new(request_uri)

          request.body = test_body

          response = http.request request

          expect(response.code).to eq '200'
          expect(response.body.length).to eq test_body.length
          expect(response.body).to eq test_body

          finished += 1
        end
      end)
    end

    until threadgroup.list.all? {|thread| thread.status.eql? false} do
      sleep 0.1
    end

    expect(finished).to be 10
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