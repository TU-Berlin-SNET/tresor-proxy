class Tresor::Backend::TCTPDiscoveryBackendHandler < Tresor::Backend::BackendHandler
  def initialize(backend)
    @backend = backend

    @http_parser = HTTP::Parser.new

    @tctp_host = false
    @tctp_discovery_information = Tresor::TCTP::DiscoveryInformation.new

    @http_parser.on_headers_complete = proc do |headers|
      if @http_parser.status_code == 200 && headers['Content-Type'].eql?('text/prs.tctp-discovery')
        log.info (log_key) { "Host #{@backend.host} (#{@backend.connection_pool_key} is TCTP capable!" }

        @tctp_host = true
      else
        log.info (log_key) { "Host #{@backend.host} (#{@backend.connection_pool_key}) does not support TCTP." }
      end
    end

    @http_parser.on_body = proc do |chunk|
      if @tctp_host
        @tctp_discovery_information.raw_data.write chunk
      end
    end

    @http_parser.on_message_complete = proc do |env|
      if @tctp_host
        @tctp_discovery_information.transform_raw_data!

        Tresor::TCTP.host_discovery_information[@backend.host] = @tctp_discovery_information
      else
        Tresor::TCTP.host_discovery_information[@backend.host] = false
      end

      #Let backend reevaluate what to do
      @backend.decide_handler

      #Mark for garbage collection
      @backend = nil
      @http_parser = nil
      @tctp_discovery_information = nil
    end

    log.debug (log_key) { "Sending TCTP discovery to #{@backend.host}" }

    @backend.send_data "OPTIONS /* HTTP/1.1\r\n"
    @backend.send_data "Host: #{@backend.host}\r\n"
    @backend.send_data "Accept: text/prs.tctp-discovery\r\n"
    @backend.send_data "\r\n"

    @backend.receive_data_future.succeed self
  end

  def receive_data(data)
    @http_parser << data
  end

  def log_key
    "Thread #{Thread.list.index(Thread.current)} - #{@backend.proxy.name} - TCTP Discovery"
  end

  def self.finalize(id)
    puts "TCTPDiscoveryBackendHandler #{id} finalized"
  end
end