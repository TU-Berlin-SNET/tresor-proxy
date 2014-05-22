class Tresor::Backend::TCTPDiscoveryBackendHandler < Tresor::Backend::BackendHandler
  # @param [Tresor::Backend::Backend]
  def initialize(backend)
    super(backend)

    @tctp_host = false
    @tctp_discovery_information = Tresor::TCTP::DiscoveryInformation.new

    backend_connection_future.callback do |backend_connection|
      log.debug (log_key) { "Sending TCTP discovery to #{backend.client_connection.host}" }

      backend_connection.send_data "OPTIONS /* HTTP/1.1\r\n"
      backend_connection.send_data "Host: #{backend.client_connection.host}\r\n"
      backend_connection.send_data "Accept: text/prs.tctp-discovery\r\n"
      backend_connection.send_data "\r\n"
    end
  end

  def on_backend_headers_complete(headers)
    @headers = headers

    if backend_connection.http_parser.status_code == 200 && headers['Content-Type'].eql?('text/prs.tctp-discovery')
      log.info (log_key) { "Host #{backend.client_connection.host} (#{backend_connection.connection_pool_key} is TCTP capable!" }

      @tctp_host = true
    else
      log.info (log_key) { "Host #{backend.client_connection.host} (#{backend_connection.connection_pool_key}) does not support TCTP." }
    end
  end

  def on_backend_body(chunk)
    if @tctp_host
      @tctp_discovery_information.raw_data.write chunk
    end
  end

  def on_backend_message_complete
    if @tctp_host
      @tctp_discovery_information.transform_raw_data!

      Tresor::TCTP.host_discovery_information[backend.client_connection.host] = @tctp_discovery_information
    else
      Tresor::TCTP.host_discovery_information[backend.client_connection.host] = false
    end

    #Let backend reevaluate what to do
    backend.decide_handler
  end

  def log_key
    "Thread #{Thread.list.index(Thread.current)} - #{@backend.proxy.name} - TCTP Discovery"
  end

  def self.finalize(id)
    puts "TCTPDiscoveryBackendHandler #{id} finalized"
  end
end