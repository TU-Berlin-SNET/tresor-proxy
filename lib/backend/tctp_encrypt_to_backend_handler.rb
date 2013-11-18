require_relative '../tctp/sequence_queue'

class Tresor::Backend::TCTPEncryptToBackendHandler < Tresor::Backend::BackendHandler
  def initialize(backend, halec_promise)
    @backend = backend
    @halec_promise = halec_promise

    @http_parser = HTTP::Parser.new

    start_line = build_start_line

    log.debug (log_key) { "Encrypting to backend: #{start_line[0..-2]}" }

    cookie = @backend.proxy.halec_registry.get_tctp_cookie(backend.host)
    tctp_cookie_sent = false

    @backend.send_data start_line
    @backend.client_headers.each do |header, value|
      next if header.eql?('Accept-Encoding')
      if header.eql?('Cookie') && cookie
        value = "#{value}; #{cookie}"
        tctp_cookie_sent = true
      end

      @backend.send_data "#{header}: #{value}\r\n"
    end
    @backend.send_data "Cookie: #{cookie}\r\n" unless tctp_cookie_sent
    @backend.send_data 'Accept-Encoding: encrypted'
    @backend.send_data "\r\n\r\n"

    @http_parser.on_headers_complete = proc do |headers|
      @backend.plexer.relay_from_backend "HTTP/1.1 #{@http_parser.status_code}\r\n"

      headers.each do |header, value|
        if %w[Transfer-Encoding Content-Length].include? header
          @has_body = true

          next
        end

        if header.eql? 'Content-Encoding'
          @encrypted_response = value.eql? 'encrypted'
        else
          @backend.plexer.relay_from_backend "#{header}: #{value}\r\n"
        end
      end

      unless @encrypted_response
        log.warn (log_key) {"Got unencrypted response from #{backend.host} (#{backend.connection_pool_key}) for encrypted request!"}
      end

      @backend.plexer.relay_from_backend "Transfer-Encoding: chunked\r\n" if @has_body

      @backend.plexer.relay_from_backend "\r\n"
    end

    @first_chunk = true
    @message_complete = false

    @http_parser.on_body = proc do |chunk|
      if(@encrypted_response)
        log.debug (log_key) {"Got #{chunk.length} encrypted bytes HTTP body"}

        # On first chunk: Get the HALEC URL, redeem the promise (get the corresponding HALEC) and set up the HALEC to write
        # unencrypted data as chunks back to the client.
        if @first_chunk
          first_newline_index = chunk.index("\r\n")
          body_halec_url = chunk[0, first_newline_index]

          log.debug (log_key) { "Body was encrypted using HALEC #{body_halec_url}" }

          @halec = @halec_promise.redeem_halec(body_halec_url)
          @halec_data_index = @halec.data_to_be_decrypted.sequence_index
          @halec_decrypted_data = Tresor::TCTP::SequenceQueue.new(@halec_data_index)

          #@halec.on_decrypted_data_read = proc do |decrypted_data|
          #  unless decrypted_data.eql?(:finished)
          #    relay_as_chunked decrypted_data
          #  else
          #    if @message_complete
          #      finish_response
          #
          #      @http_parser.reset!
          #    end
          #  end
          #end

          chunk_without_url = chunk[(first_newline_index + 2)..-1]

          unless chunk_without_url.eql?('')
            log.debug (log_key) { "Pushing #{chunk_without_url.size} bytes chunk ##{@halec_data_index} to data_to_be_decrypted queue." }

            @halec.data_to_be_decrypted.push chunk_without_url, @halec_data_index
            @halec_data_index += 1

            send_decrypted_data
          end

          @first_chunk = false
        else
          log.debug (log_key) { "Pushing #{chunk.size} bytes chunk ##{@halec_data_index} to data_to_be_decrypted queue." }

          @halec.data_to_be_decrypted.push chunk, @halec_data_index
          @halec_data_index += 1

          send_decrypted_data
        end
      else
        relay_as_chunked(chunk)
      end
    end

    @http_parser.on_message_complete = proc do |env|
      log.debug (log_key) { "Finished receiving backend response to #{@backend.client_method} #{@backend.client_path}#{@backend.client_query_string ? "?#{@backend.client_query_string}": ''}." }

      log.debug (log_key) { "Pushing :eof chunk ##{@halec_data_index} to data_to_be_decrypted queue." }

      @halec.data_to_be_decrypted.push :eof, @halec_data_index
      @halec_data_index += 1

      send_decrypted_data
    end

    @backend.client_chunk_future.succeed self
    @backend.receive_data_future.succeed self
  end

  def send_decrypted_data
    @halec.decrypt_data.callback do |decrypted_data_hash|
      decrypted_data_hash.each do |sequence_no, decrypted_data|
        @halec_decrypted_data.push decrypted_data, sequence_no
      end

      @halec_decrypted_data.shift_next_items.each do |sequence_no, decrypted_data|
        unless decrypted_data.eql?(:eof)
          decrypted_data.each do |decrypted_data_item|
            log.debug (log_key) { "Relaying #{decrypted_data_item.length} bytes decrypted data item from chunk ##{sequence_no} of #halec_decrypted_data queue." }

            relay_as_chunked decrypted_data_item
          end
        else
          log.debug (log_key) { "Got :eof as chunk ##{sequence_no} of #halec_decrypted_data queue, finishing response." }

          finish_response
        end
      end
    end
  end

  def relay_as_chunked(data)
    chunk_length_as_hex = data.length.to_s(16)

    log.debug (log_key) { "Relaying #{data.length} (#{chunk_length_as_hex}) bytes of data from backend to client" }

    @backend.plexer.relay_from_backend chunk_length_as_hex
    @backend.plexer.relay_from_backend "\r\n"
    @backend.plexer.relay_from_backend data
    @backend.plexer.relay_from_backend "\r\n"
  end

  def finish_response
    log.info (log_key) { 'Sending trailer to client' }

    @backend.plexer.relay_from_backend "0\r\n\r\n" if @has_body

    if @encrypted_response
      @halec_promise.return
    end

    @backend.free_backend
  end

  def receive_data(data)
    log.debug (log_key) { "Feeding #{data.length} bytes of encrypted data to HTTP parser" }

    @http_parser << data
  end

  def log_key
    "Thread #{Thread.list.index(Thread.current)} - #{@backend.proxy.name} - TCTP Encrypt to Backend handler"
  end
end