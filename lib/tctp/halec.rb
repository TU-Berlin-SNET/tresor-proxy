require 'eventmachine'
require 'io/wait'

module Tresor
  module TCTP
    class HALEC
      attr_accessor :url
      attr_accessor :handshake_complete

      # The plaintext socket
      attr_reader :socket_here

      # The SSL socket
      attr_reader :ssl_socket

      # The encrypted socket
      attr_reader :socket_there

      attr_reader :encrypted_data_read_queue

      attr_reader :decrypted_data_reads_finished

      attr_accessor :on_encrypted_data_received

      # Callback, when the handshake is complete
      attr_reader :halec_handshake_complete

      def initialize
        @ctx = OpenSSL::SSL::SSLContext.new()

        @ctx.ssl_version = :TLSv1

        @socket_here, @socket_there = socket_pair
        [@socket_here, @socket_there].each do |socket|
          socket.set_encoding(Encoding::BINARY)
        end

        @encrypted_data_read_queue = EventMachine::Queue.new
        @halec_handshake_complete = EventMachine::DefaultDeferrable.new

        reset

        @ssl_socket = OpenSSL::SSL::SSLSocket.new(@socket_here, @ctx)

        EM.defer do
          begin
            while true
              begin
                read_data = @socket_there.read_nonblock(2 ** 24)

                log.debug (log_key) {"Read #{read_data.length} bytes from encrypted socket."}

                log_state

                @encrypted_data_read_queue.push read_data
              rescue Errno::EWOULDBLOCK
                IO.select([@socket_there])

                retry
              end
            end
          rescue Exception => e
            log.warn (log_key) {"Exception #{e}"}
          end
        end

        EM.defer do
          @ssl_socket.connect

          log.debug(log_key) {'SSL Socket connected.'}

          @halec_handshake_complete.succeed

          EM.defer do
            begin
              while true
                begin
                  read_data = @ssl_socket.read_nonblock(2 ** 16)

                  log.debug (log_key) {"Read #{read_data.length} bytes plaintext (#{read_data[0..10]}..#{read_data[-10..-1]}) from SSL socket."}

                  log_state

                  @on_encrypted_data_received.call read_data

                  if(read_data.length < 2 ** 16)
                    log.debug (log_key) { 'Decrypted data reads finished' }

                    @decrypted_data_reads_finished.succeed
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

      def reset
        @on_encrypted_data_received = proc do |encrpyted_data|
          debug.warn (log_key) { "No handler set for HALEC #on_encrypted_data_received. Discarding #{encrpyted_data.size} bytes plaintext" }
        end

        @decrypted_data_reads_finished = EventMachine::DefaultDeferrable.new
      end

      private
        def socket_pair
          Socket.pair(:UNIX, :STREAM, 0) # Linux
        rescue Errno::EAFNOSUPPORT
          Socket.pair(:INET, :STREAM, 0) # Windows
        end
    end
  end
end