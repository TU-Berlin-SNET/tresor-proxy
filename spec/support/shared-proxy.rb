require 'net/http'

shared_examples 'a TRESOR proxy' do
  let :after_get_expectation do
    Proc.new do end
  end

  let :after_post_expectation do
    Proc.new do end
  end

  it 'can be used to issue forward GET requests' do
    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    request = Net::HTTP::Get.new(request_uri)

    begin
      response = http.request request
    rescue Exception => e
      fail
    end

    expect(response.code).to eq '200'
    expect(response.body).to eq 'Success /'

    after_get_expectation.call
  end

  it 'does not confuse requests and responses' do
    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    http.start
    http.keep_alive_timeout = 60

    5.times do
      Thread.new do
        5.times do
          random_string = rand(100000).to_s
          request = Net::HTTP::Get.new("#{request_uri}/#{random_string}")

          begin
            response = http.request request
          rescue Exception => e
            fail
          end

          expect(response.code).to eq '200'
          expect(response.body).to eq "Success /#{random_string}"

          after_get_expectation.call
        end
      end
    end
  end

  it 'can be used to issue forward POST requests' do
    http = Net::HTTP.new(proxy_uri.host, proxy_uri.port)
    request = Net::HTTP::Post.new(request_uri)

    @test_server.current_post_body = test_body
    request.body = test_body

    response = http.request request

    expect(response.code).to eq '200'
    expect(response.body.length).to eq test_body.length
    expect(response.body).to eq test_body

    after_post_expectation.call
  end
end