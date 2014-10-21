require_relative 'spec_helper'
require_relative 'sso_test_server'
require_relative 'xacml_pdp_mock_server'

require 'webrick'
require 'net/http'
require 'uri'
require 'rack-tctp'

describe 'An XACML PEP proxy' do
  before(:all) do
    @proxy = Tresor::Proxy::TresorProxy.new '127.0.0.1', 'proxy.local', '43220', 'XACML PEP Server'

    @proxy.log.level = Logger::DEBUG
    @proxy.is_xacml_enabled = true
    @proxy.xacml_pdp_rest_url = 'http://127.0.0.1:43221'

    @proxy.reverse_mappings = {
        'ssoserver:43220' => 'http://127.0.0.1:43222'
    }

    @proxy.sso_sessions = {
        'testsession' => Tresor::Frontend::ClaimSSO::ClaimSSOSecurityToken.new(ERB.new(File.read(File.join(__dir__, 'support', 'test_sso_token.erb'))).result)
    }

    SSO_TEST_SERVER = Tresor::SSOTestServer.new
    @test_server = SSO_TEST_SERVER

    XACML_PDP_MOCK_SERVER = Tresor::XACMLPDPMockServer.new
    @xacml_pdp_mock_server = XACML_PDP_MOCK_SERVER

    @rack_stack_sso = Rack::Builder.new do
      run SSO_TEST_SERVER
    end

    @rack_stack_xacml = Rack::Builder.new do
      run XACML_PDP_MOCK_SERVER
    end

    @webrick_sso_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43222, :ServerName => 'ssoserver'})
    @webrick_sso_server.mount '/', Rack::Handler::WEBrick, @rack_stack_sso.to_app

    @webrick_xacml_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43221, :ServerName => 'ssoserver'})
    @webrick_xacml_server.mount '/', Rack::Handler::WEBrick, @rack_stack_xacml.to_app

    Thread.new do @proxy.start end
    Thread.new do @webrick_sso_server.start end
    Thread.new do @webrick_xacml_server.start end

    sleep 2
  end

  after(:all) do
    @proxy.stop
    @webrick_sso_server.stop
    @webrick_xacml_server.stop

    sleep 2
  end

  it 'relays if XACML response is permit' do
    http = Net::HTTP.new('127.0.0.1', '43220')
    request = Net::HTTP::Get.new('/')
    request['Host'] = 'ssoserver:43220'
    request['Cookie'] = 'tresor_sso_id=testsession'

    Tresor::XACMLPDPMockServer.mock_action = :permit

    begin
      response = http.request request
    rescue Exception => e
      fail
    end

    expect(response.code).to eq '200'
    expect(response.body).to eq 'Success'
  end

  it 'errs if XACML response is deny' do
    http = Net::HTTP.new('127.0.0.1', '43220')
    request = Net::HTTP::Get.new('/')
    request['Host'] = 'ssoserver:43220'
    request['Cookie'] = 'tresor_sso_id=testsession'

    Tresor::XACMLPDPMockServer.mock_action = :deny

    begin
      response = http.request request
    rescue Exception => e
      fail
    end

    expect(response.code).to eq '403'
    expect(response.body).to eq 'Forbidden'
  end
end