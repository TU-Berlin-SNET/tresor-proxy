#require_relative 'spec_helper'
#
#require_relative '../lib/tresor_proxy'
#require_relative 'test_server'
#
#require 'thin'
#require 'net/http'
#require 'uri'
#require 'faker'
#
#describe 'A basic forward proxy' do
#  before(:all) do
#    @proxy = Tresor::TresorProxy.new '127.0.0.1', '43208', 'Basic test proxy'
#    BASIC_FORWARD_TEST_SERVER = Tresor::TestServer.new
#
#    @thin_server = Thin::Server.new '127.0.0.1', 43209, @test_server
#
#    Thread.new do @proxy.start end
#    Thread.new do @thin_server.start end
#    until @proxy.started do Thread.pass end
#    until @thin_server.running? do Thread.pass end
#  end
#
#  after(:all) do
#    @proxy.stop
#    @thin_server.stop
#
#    while @proxy.started do Thread.pass end
#    while @thin_server.running? do Thread.pass end
#  end
#
#  let :proxy_uri do
#    URI.parse('http://127.0.0.1:43208')
#  end
#
#  let :request_uri do
#    'http://127.0.0.1:43209'
#  end
#
#  it 'can be started' do
#    expect(@proxy.started).to be_true
#  end
#
#  it 'returns 502 error when trying to access a not configured reverse host' do
#    proxy_uri = URI.parse('http://127.0.0.1:43208')
#    test_server_uri = URI.parse('http://127.0.0.1:43209')
#
#    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
#    request = Net::HTTP::Get.new(test_server_uri)
#
#    response = http.request request
#
#    expect(response.code).to eq '502'
#  end
#end