require_relative 'sequence_queue'

class Tresor::TCTP::HALEC
  attr_accessor :url

  # The plaintext socket
  attr_reader :socket_here

  # The SSL socket
  attr_reader :ssl_socket

  # The encrypted socket
  attr_reader :socket_there

  # Callback, when the handshake is complete
  attr_reader :halec_handshake_complete

  # Mutex for HALEC
  attr_accessor :halec_mutex

  # Queues. Items can either be a string, nil, or :eof
  attr_accessor :data_to_be_encrypted
  attr_accessor :data_to_be_decrypted

  def initialize(options = {})
    @url = options[:url] || ''
    @ctx = options[:ssl_context] || OpenSSL::SSL::SSLContext.new()
    @halec_mutex = Mutex.new

    @data_to_be_encrypted = Tresor::TCTP::SequenceQueue.new
    @data_to_be_decrypted = Tresor::TCTP::SequenceQueue.new

    @ctx.ssl_version = :TLSv1

    @socket_here, @socket_there = socket_pair
    [@socket_here, @socket_there].each do |socket|
      socket.set_encoding(Encoding::BINARY)
    end

    @halec_handshake_complete = EventMachine::DefaultDeferrable.new
  end

  def log_key
    "Thread #{Thread.list.index(Thread.current)} - HALEC #{__id__} #{@url || 'Unknown URL'}"
  end

  def log_state
    log.debug(log_key) {"Current OpenSSL state: '#{@ssl_socket.state}'"}
  end

  def decrypt_data
    decrypted_data_callback = EventMachine::DefaultDeferrable.new

    EM.defer do
      decrypted_data = {}

      next_items = @data_to_be_decrypted.shift_next_items

      unless next_items.empty?
        @halec_mutex.synchronize do
          next_items.each do |sequence_no, encrypted_data|
            if encrypted_data.eql?(:eof)
              decrypted_data[sequence_no] = :eof

              log.debug (log_key) { "##{sequence_no} was EOF"}
            else
              @socket_there.write(encrypted_data)

              decrypted_items = []

              while @socket_here.ready?
                decrypted_items.push @ssl_socket.readpartial(32768)
              end

              log.debug (log_key) { "Decrypted ##{sequence_no}" }

              decrypted_data[sequence_no] = decrypted_items
            end
          end
        end
      end

      decrypted_data_callback.succeed decrypted_data
    end

    decrypted_data_callback
  end

  def encrypt_data
    encrypted_data_callback = EventMachine::DefaultDeferrable.new

    EM.defer do
      encrypted_data = {}

      next_items = @data_to_be_encrypted.shift_next_items

      unless next_items.empty?
        @halec_mutex.synchronize do
          next_items.each do |sequence_no, data|
            if(data.eql?(:eof))
              encrypted_data[sequence_no] = :eof

              log.debug (log_key) { "##{sequence_no} was EOF" }
            else
              @ssl_socket.write(data)

              encrypted_items = []

              while @socket_there.ready?
                encrypted_items.push @socket_there.readpartial(32768)
              end

              log.debug (log_key) { "Encrypted ##{sequence_no}" }

              encrypted_data[sequence_no] = encrypted_items
            end
          end
        end
      end

      encrypted_data_callback.succeed encrypted_data
    end

    encrypted_data_callback
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