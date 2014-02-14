require_relative 'spec_helper'

require_relative '../lib/tresor_proxy'
require_relative 'test_server'

require 'thin'
require 'net/http'
require 'uri'
require 'faker'

describe 'A basic forward proxy' do
  before(:all) do
    @proxy = Tresor::TresorProxy.new '127.0.0.1', '43210', 'Basic test proxy'
    @test_server = Tresor::TestServer.new
    @thin_server = Thin::Server.new '127.0.0.1', 43211, @test_server

    Thread.new do @proxy.start end
    Thread.new do
      @thin_server.start
    end
    until @proxy.started

    end
  end

  after(:all) do
    @proxy.stop
    @thin_server.stop
  end

  it 'can be started' do
    expect(@proxy.started).to be_true
  end

  it 'can be used to issue forward GET requests' do
    proxy_uri = URI.parse('http://127.0.0.1:43210')

    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    request = Net::HTTP::Get.new('http://127.0.0.1:43211')

    response = http.request request

    expect(response.code).to eq '200'
    expect(response.body).to eq 'Success'
  end

  it 'can be used to issue forward POST requests' do
    proxy_uri = URI.parse('http://127.0.0.1:43210')

    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    request = Net::HTTP::Post.new('http://127.0.0.1:43211')

    test_body = StringIO.new

    (1..1000000).each do |x|
      test_body.write "#{x}:"
    end

    test_body_string = test_body.string

    @test_server.current_post_body = test_body_string
    request.body = test_body_string

    response = http.request request

    expect(response.code).to eq '200'
    expect(response.body).to eq test_body_string
  end

  it 'returns 502 error when trying to access a not configured reverse host' do
    proxy_uri = URI.parse('http://127.0.0.1:43210')
    test_server_uri = URI.parse('http://127.0.0.1:43211')

    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    request = Net::HTTP::Get.new(test_server_uri)

    response = http.request request

    expect(response.code).to eq '502'
  end
end