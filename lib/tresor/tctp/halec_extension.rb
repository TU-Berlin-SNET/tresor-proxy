class Rack::TCTP::HALEC
  # Proc, which is called with plaintext data available after injection
  # @!attr [rw] plaintext_proc
  # @return [Proc] plaintext_proc The Proc
  attr_accessor :plaintext_proc

  # Proc, which is called with encrypted data available after writing
  # @!attr [rw] encrypted_proc
  # @return [Proc] encrypted_proc The Proc
  attr_accessor :encrypted_proc

  # TCTP session cookie associated with this HALEC
  attr_accessor :tctp_session_cookie
end