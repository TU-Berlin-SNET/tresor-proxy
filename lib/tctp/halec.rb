class Tresor::TCTP::HALEC
  attr_accessor :url

  # The plaintext socket
  attr_reader :socket_here

  # The SSL socket
  attr_reader :ssl_socket

  # The encrypted socket
  attr_reader :socket_there

  attr_reader :encrypted_data_read_queue

  attr_accessor :on_decrypted_data_read
  attr_accessor :on_encrypted_data_read

  # Callback, when the handshake is complete
  attr_reader :halec_handshake_complete

  def initialize(options = {})
    @url = options[:url] || ''
    @ctx = options[:ssl_context] || OpenSSL::SSL::SSLContext.new()

    @ctx.ssl_version = :TLSv1

    @socket_here, @socket_there = socket_pair
    [@socket_here, @socket_there].each do |socket|
      socket.set_encoding(Encoding::BINARY)
    end

    @halec_handshake_complete = EventMachine::DefaultDeferrable.new

    reset
  end

  def reset
    @on_decrypted_data_read = proc do |decrypted_data|
      log.debug (log_key) { "No handler set for HALEC #on_decrypted_data_read. Discarding #{decrypted_data.size} bytes plaintext" }
    end

    @on_encrypted_data_read = proc do |encrpyted_data|
      log.debug (log_key) { "No handler set for HALEC #on_encrypted_data_read. Discarding #{encrpyted_data.size} bytes encrypted data" }
    end

    @decrypted_data_reads_finished = EventMachine::DefaultDeferrable.new
  end

  def log_key
    "HALEC #{__id__} #{@url || 'Unknown URL'}"
  end

  def log_state
    log.debug(log_key) {"Current OpenSSL state: '#{@ssl_socket.state}'"}
  end

  def write_encrypted_data(data)
    begin
      result = @socket_there.write_nonblock(data)

      log.debug(log_key) {"Written #{result} of #{data.length} bytes to encrypted socket."}

      log_state
    rescue Exception => e
      IO.select(nil, [@socket_there])
      retry
    end
  end

  def write_decrypted_data(data)
    begin
      result = @ssl_socket.write_nonblock(data)

      @ssl_socket.flush

      log.debug (log_key) {"Written #{result} of #{data.length} bytes to SSL socket."}

      log_state
    rescue IO::WaitReadable
      IO.select([@ssl_socket])
      retry
    rescue IO::WaitWritable
      IO.select(nil, [@ssl_socket])
      retry
    end
  end

  def begin_reading_decrypted_data
    EM.defer do
      begin
        while true
          begin
            read_data = @ssl_socket.read_nonblock(2 ** 12)

            log.debug (log_key) {"Read #{read_data.length} bytes plaintext from SSL socket."}

            log_state

            @on_decrypted_data_read.call read_data

            if(read_data.length < 2 ** 12 && @socket_here.ready? == false)
              log.debug (log_key) { 'Decrypted data reads finished' }

              @on_decrypted_data_read.call :finished
            end
          rescue IO::WaitReadable
            IO.select([@ssl_socket])
            retry
          rescue IO::WaitWritable
            IO.select(nil, [@ssl_socket])
            retry
          end
        end
      rescue Exception => e
        log.warn (log_key) {"Exception #{e}"}
      end
    end
  end

  def begin_reading_encrypted_data
    EM.defer do
      begin
        while true
          begin
            read_data = @socket_there.read_nonblock(2 ** 24)

            log.debug (log_key) {"Read #{read_data.length} bytes from encrypted socket."}

            log_state

            @on_encrypted_data_read.call read_data
          rescue Errno::EWOULDBLOCK
            IO.select([@socket_there])

            retry
          end
        end
      rescue Exception => e
        log.warn (log_key) {"Exception #{e}"}
      end
    end
  end

  private
    def socket_pair
      begin
        Socket.pair(:UNIX, :STREAM, 0) # Linux
      rescue Errno::EAFNOSUPPORT
        Socket.pair(:INET, :STREAM, 0) # Windows
      end
    end
end