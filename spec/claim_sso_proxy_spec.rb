require_relative 'spec_helper'
require_relative 'sso_test_server'

require 'webrick'
require 'net/http'
require 'uri'
require 'rack-tctp'

describe 'An SSO proxy' do
  before(:all) do
    @proxy = Tresor::Proxy::TresorProxy.new '127.0.0.1', 'proxy.local', '43217', 'SSO client proxy'

    @proxy.log.level = Logger::DEBUG
    @proxy.is_sso_enabled = true
    @proxy.fpurl = 'http://federation-provider.local'
    @proxy.hrurl = 'http://home-realm.local'
    @proxy.reverse_mappings = {nil => 'http://127.0.0.1:43218'}

    SSO_TEST_SERVER = Tresor::SSOTestServer.new
    @test_server = SSO_TEST_SERVER

    @rack_stack = Rack::Builder.new do
      run SSO_TEST_SERVER
    end

    @webrick_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43218})
    @webrick_server.mount '/', Rack::Handler::WEBrick, @rack_stack.to_app

    Thread.new do @proxy.start end
    Thread.new do @webrick_server.start end

    until @proxy.started do sleep 0.1 end
    until @webrick_server.status.eql? :Running do sleep 0.1 end
  end

  it 'does not redirect if accessed by main hostname' do
    http = Net::HTTP.new('127.0.0.1', '43217')
    request = Net::HTTP::Get.new('/')
    request['Host'] = 'proxy.local'

    begin
      response = http.request request
    rescue Exception => e
      fail
    end

    expect(response.code).to eq '200'
    expect(response.body).to eq Tresor::Frontend::TresorProxyFrontendHandler.build_hello_message
  end

  it 'redirects to SSO if it is configured to reverse proxy the requested hostname' do
    http = Net::HTTP.new('127.0.0.1', '43217')
    request = Net::HTTP::Get.new('/')
    request['Host'] = 'webrick.local'

    begin
      response = http.request request
    rescue Exception => e
      fail
    end

    expect(response.code).to eq '302'

    location_url = URI(response['Location'])
    expect(location_url.host).to eq 'federation-provider.local'

    query_string_parts = Hash[location_url.query.split('&').map {|p| p.split('=')}]

    expect(query_string_parts['wa']).to eq 'wsignin1.0'
    expect(query_string_parts['wtrealm']).to eq URI.encode_www_form_component('http://proxy.local/?wdycf_url=http://webrick.local/')
    expect(query_string_parts['whr']).to eq URI.encode_www_form_component('http://home-realm.local')
  end

  it 'redirects to wdycf URL and saves the SSO token' do
    http = Net::HTTP.new('127.0.0.1', '43217')
    request = Net::HTTP::Post.new("/?wdycf_url=#{URI.encode_www_form_component('http://webrick.local/')}")
    request['Host'] = 'proxy.local'

    sso_token = ERB.new(File.read(File.join(__dir__, 'support', 'test_sso_token.erb'))).result

    request.body = "wresult=#{URI.encode_www_form_component(sso_token)}"

    begin
      response = http.request request
    rescue Exception => e
      fail
    end

    expect(response.code).to eq '302'
  end

  it 'sends an error message, if no token is given' do
    http = Net::HTTP.new('127.0.0.1', '43217')
    request = Net::HTTP::Post.new("/?wdycf_url=#{URI.encode_www_form_component('http://webrick.local/')}")
    request['Host'] = 'proxy.local'

    begin
      response = http.request request
    rescue Exception => e
      fail
    end

    expect(response.code).to eq '502'
    expect(response.body).to eq 'SSO token missing'
  end

  after(:all) do
    @proxy.stop
    @webrick_server.stop

    while @proxy.started do sleep 0.1 end
    until @webrick_server.status.eql? :Stop do sleep 0.1 end
  end
end