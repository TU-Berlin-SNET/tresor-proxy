require 'radix'

class Tresor::TCTP::ServerHALEC < Tresor::TCTP::HALEC
  def initialize(options = {})
    super(options)

    if(options[:private_key] && options[:certificate])
      @private_key = options[:private_key]
      @certificate = options[:certificate]
    else
      @private_key = self.class.default_key
      @certificate = self.class.default_self_signed_certificate
    end

    @ctx.cert = @certificate
    @ctx.key = @private_key

    unless @ctx.session_id_context
      # see #6137 - session id may not exceed 32 bytes
      prng = ::Random.new($0.hash)
      session_id = prng.bytes(16).unpack('H*')[0]
      @ctx.session_id_context = session_id
    end

    @ssl_socket = OpenSSL::SSL::SSLSocket.new(@socket_here, @ctx)

    EM.defer do
      @ssl_socket.accept

      log.debug(log_key) {'SSL Socket connected.'}

      @halec_handshake_complete.succeed

      begin_reading_decrypted_data
    end
  end

  class << self
    @default_key
    @default_self_signed_certificate

    def initialize
      default_key
      default_self_signed_certificate

      self
    end

    def default_key
      @default_key ||= OpenSSL::PKey::RSA.new 2048
    end

    def default_self_signed_certificate
      @default_self_signed_certificate ||= generate_self_signed_certificate
    end

    def generate_self_signed_certificate
      name = OpenSSL::X509::Name.parse 'CN=tctp-server/DC=tctp'

      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 0
      cert.not_before = Time.now
      cert.not_after = Time.now + 3600

      cert.public_key = @default_key.public_key
      cert.subject = name

      cert
    end

    # The slug URI can contain any HTTP compatible characters
    def slug_base
      Radix::Base.new(Radix::BASE::B62 + ['-', '_'])
    end

    # Generate a new random slug (2^64 possibilities)
    def new_slug
      slug_base.convert(rand(2**64), 10)
    end
  end
end