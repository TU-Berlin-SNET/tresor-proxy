require_relative 'spec_helper'

require_relative '../lib/tresor_proxy'
require_relative 'test_server'

require 'webrick'
require 'thin'
require 'net/http'
require 'uri'
require 'rack-tctp'

describe 'A tctp server proxy' do
  before(:all) do
    @proxy = Tresor::TresorProxy.new '127.0.0.1', '43215', 'TCTP server proxy'

    @proxy.is_tctp_server = true
    @proxy.reverse_mappings = { '127.0.0.1' => 'http://127.0.0.1:43216' }

    SERVER_PROXY_TEST_SERVER = Tresor::TestServer.new
    @test_server = SERVER_PROXY_TEST_SERVER

    @rack_stack = Rack::Builder.new do
      run SERVER_PROXY_TEST_SERVER
    end

    @webrick_server = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => 43216})
    @webrick_server.mount '/', Rack::Handler::WEBrick, @rack_stack.to_app

    Thread.new do @proxy.start end
    Thread.new do @webrick_server.start end

    until @proxy.started do Thread.pass end
    until @webrick_server.status.eql? :Running do Thread.pass end
  end

  after(:all) do
    puts "After tctp server proxy"

    @proxy.stop
    @webrick_server.stop

    while @proxy.started do Thread.pass end
    until @webrick_server.status.eql? :Stop do Thread.pass end
  end

  it 'can be used to issue forward GET and POST request' do
    client_halec = Rack::TCTP::ClientHALEC.new()

    # Receive the TLS client_hello
    client_halec.engine.read
    client_hello = client_halec.engine.extract

    # Post the client_hello to the HALEC creation URI, starting the handshake
    http = Net::HTTP.new('127.0.0.1', '43215')
    request = Net::HTTP::Post.new('/halecs')
    request.body = client_hello

    response = http.request request

    expect(response.code).to eq '200'

    # The HALEC URL is returned as Location header
    halec_url = response['Location']

    # Feed the handshake response (server_hello, certificate, etc.) from the entity-body to the client HALEC
    client_halec.engine.inject response.body

    # Read the TLS client response (client_key_exchange, change_cipher_spec, finished)
    client_halec.engine.read
    client_response = client_halec.engine.extract

    # Post the TLS client response to the HALEC url
    request = Net::HTTP::Post.new(URI(halec_url).path)
    request.body = client_response

    response = http.request request

    expect(response.code).to eq '200'

    # Feed the handshake response (change_cipher_spec, finished) to the client HALEC
    client_halec.engine.inject response.body

    # The handshake is now complete!

    request = Net::HTTP::Get.new('/')
    request['Accept-Encoding'] = 'encrypted'

    response = http.request(request)

    # The TCTP encrypted HTTP entity-body
    body_stream = StringIO.new(response.body)

    # Read first line (the Halec URL ... we know it already)
    url = body_stream.readline

    expect(url.chomp).to eql(halec_url)

    # Read the decrypted body
    decrypted_body = client_halec.decrypt_data body_stream.read

    expect(decrypted_body).to eql('Success')

    # Creates a POST body
    @test_server.current_post_body = test_body

    # Create encrypted body
    encrypted_body_io = StringIO.new
    encrypted_body_io.write "#{halec_url}\r\n"

    # Encrypts plaintext_test_body
    encrypted_body_io.write client_halec.encrypt_data(test_body)

    request = Net::HTTP::Post.new('/')
    request.body = encrypted_body_io.string
    request['Accept-Encoding'] = 'encrypted'
    request['Content-Encoding'] = 'encrypted'

    response = http.request request

    # Create a stream from the response body
    body_stream = StringIO.new(response.body)

    # Read first line (the Halec URL ... we know it already)
    url = body_stream.readline

    expect(url.chomp).to eql(halec_url)

    # Write the rest of the stream to the client HALEC
    decrypted_body = client_halec.decrypt_data(body_stream.read)

    # Compares the response
    expect(decrypted_body).to eql(test_body)
  end
end