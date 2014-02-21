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
    @proxy = Tresor::TresorProxy.new '127.0.0.1', '43210', 'TCTP server proxy'

    @proxy.is_tctp_server = true
    @proxy.reverse_mappings = { '127.0.0.1' => 'http://127.0.0.1:43211' }

    TEST_SERVER = Tresor::TestServer.new
    @test_server = TEST_SERVER

    @rack_stack = Rack::Builder.new do
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

  it 'can be used to issue forward GET and POST request' do
    client_halec = ClientHALEC.new()

    # Connect sends out the handshake, but would block until handshake is completed. Therefore the connect is run in
    # another thread.
    Thread.new {
      begin
        client_halec.ssl_socket.connect
      rescue Exception => e
        puts e
      end
    }

    # Receive the TLS client_hello
    client_hello = client_halec.socket_there.recv(1024)

    # Post the client_hello to the HALEC creation URI, starting the handshake
    http = Net::HTTP.new('127.0.0.1', '43210')
    request = Net::HTTP::Post.new('/halecs')
    request.body = client_hello

    response = http.request request

    expect(response.code).to eq '200'

    # The HALEC URL is returned as Location header
    halec_url = response['Location']

    # Feed the handshake response (server_hello, certificate, etc.) from the entity-body to the client HALEC
    client_halec.socket_there.write(response.body)

    # Read the TLS client response (client_key_exchange, change_cipher_spec, finished)
    client_response = client_halec.socket_there.recv(2048)

    # Post the TLS client response to the HALEC url
    request = Net::HTTP::Post.new(URI(halec_url).path)
    request.body = client_response

    response = http.request request

    expect(response.code).to eq '200'

    # Feed the handshake response (change_cipher_spec, finished) to the client HALEC
    client_halec.socket_there.write(response.body)

    # The handshake is now complete!

    request = Net::HTTP::Get.new('/')
    request['Accept-Encoding'] = 'encrypted'

    response = http.request(request)

    # The TCTP encrypted HTTP entity-body
    body_stream = StringIO.new(response.body)

    # Read first line (the Halec URL ... we know it already)
    url = body_stream.readline

    expect(url.chomp).to eql(halec_url)

    # Write the rest of the stream to the client HALEC
    body_encrypted = body_stream.readpartial(1024*1024)
    client_halec.socket_there.write(body_encrypted)

    # Read the decrypted body
    decrypted_body = client_halec.ssl_socket.readpartial(1024*1024)

    expect(decrypted_body).to eql('Success')

    # Creates a POST body
    plaintext_test_body = StringIO.new
    (1..10000).each do |x|
      plaintext_test_body.write "#{x}:"
    end

    test_body_string = plaintext_test_body.string
    @test_server.current_post_body = test_body_string

    # Create encrypted body
    encrypted_body_io = StringIO.new
    encrypted_body_io.write "#{halec_url}\r\n"

    # Encrypts plaintext_test_body
    to_write = test_body_string.bytesize
    written = 0
    until written == to_write
      written += client_halec.ssl_socket.write_nonblock(test_body_string[written, to_write])
      encrypted_test_body_string = client_halec.socket_there.read_nonblock(1024*1024)
      encrypted_body_io.write(encrypted_test_body_string)
    end

    request = Net::HTTP::Post.new('/')
    request.body = encrypted_body_io.string
    request['Accept-Encoding'] = 'encrypted'
    request['Content-Encoding'] = 'encrypted'

    # Mock Accept-Encoding 'encrypted'
    response = http.request request

    # Create a stream from the response body
    body_stream = StringIO.new(response.body)

    # Read first line (the Halec URL ... we know it already)
    url = body_stream.readline

    expect(url.chomp).to eql(halec_url)

    # Write the rest of the stream to the client HALEC
    body_encrypted = body_stream.read
    client_halec.socket_there.write(body_encrypted)
    client_halec.socket_there.close

    # Read the decrypted body
    decrypted_body = StringIO.new
    until @allread
      begin
        decrypted_body.write client_halec.ssl_socket.readpartial(1024*1024)
      rescue Exception => e
        @allread = true
      end
    end

    # Compares the response
    expect(decrypted_body.string).to eql(test_body_string)
  end
end