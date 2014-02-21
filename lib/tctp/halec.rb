require_relative 'sequence_queue'

require 'fiber'

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

  def initialize(options = {})
    @url = options[:url] || nil
    @ctx = options[:ssl_context] || OpenSSL::SSL::SSLContext.new()
    @halec_mutex = Mutex.new

    @ctx.ssl_version = :TLSv1

    @socket_here, @socket_there = socket_pair
    [@socket_here, @socket_there].each do |socket|
      socket.set_encoding(Encoding::BINARY)
    end

    @halec_handshake_complete = EventMachine::DefaultDeferrable.new
  end

  def log_key
    "HALEC #{__id__} #{@url || 'Unknown URL'}"
  end

  def log_state
    log.debug(log_key) {"Current OpenSSL state: '#{@ssl_socket.state}'"}
  end

  # Decrypts encrypted data
  # @param data [String] The encrypted data
  # @return [String] The decrypted data
  def decrypt_data(data)
    @socket_there.write(data)

    decrypted_items = []

    #If badly chunked, we do not have any data
    begin
      while true
        decrypted_items.push @ssl_socket.read_nonblock(32768)
      end
    rescue Exception => e
      unless @ssl_socket.state =~ /SSLOK/
        log.error (log_key) { "Error while decrypting data: #{e}" }
      end
    end

    exit if decrypted_items.empty?

    decrypted_items.join
  end

  # Encrypts plaintext
  # @param data [String] The plaintext
  # @return [String] The encrypted data
  def encrypt_data(data)
    @ssl_socket.write(data)

    encrypted_items = []

    while @socket_there.ready?
      encrypted_items.push @socket_there.readpartial(32768)
    end

    encrypted_items.join
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