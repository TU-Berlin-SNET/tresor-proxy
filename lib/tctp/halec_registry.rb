module Tresor
  module TCTP
    module HALECRegistry
      @@halecs = {}
      @@halec_promises = {}
      @@tctp_cookies = {}

      def self.promise_for(host, resource_url)
        handshake_url = Tresor::TCTP.handshake_url(host, resource_url)

        free_halecs = halecs(handshake_url)
        free_halec_promises = halec_promises(handshake_url)

        if free_halec_promises.count >= free_halecs.count
          raise HALECUnavailable.new
        else
          free_halec_promises[free_halec_promises.length] = HALECPromise.new(host, handshake_url)
        end
      end

      def self.return_halec_promise(promise)
        halec_promises(promise.handshake_url).delete(promise)
      end

      def self.get_tctp_cookie(host)
        @@tctp_cookies[host]
      end

      def self.register_tctp_cookie(host, cookie)
        @@tctp_cookies[host] = cookie
      end

      def self.register_halec(handshake_url, halec)
        @@halecs[handshake_url][halec.url] = halec

        @@tctp_cookies[halec]
      end

      class HALECPromise
        attr_accessor :host
        attr_accessor :handshake_url

        def initialize(host, handshake_url)
          @host = host
          @handshake_url = handshake_url
        end

        def redeem_halec(halec_url = nil)
          if halec_url
            HALECRegistry.halecs(@handshake_url)[halec_url]
          else
            HALECRegistry.halec_for(@host, @handshake_url)
          end
        end

        def return_halec(halec)
          HALECRegistry.halecs(@handshake_url)[halec.url] = halec
        end
      end

      private
        def self.halec_for(host, resource_url)
          handshake_url = Tresor::TCTP.handshake_url(host, resource_url)

          free_halecs = halecs(handshake_url)

          if free_halecs.count == 0
            raise HALECUnavailable.new
          else
            free_halecs.shift[1]
          end
        end

        def self.halecs(handshake_url)
          @@halecs[handshake_url] ||= {}
        end

        def self.halec_promises(handshake_url)
          @@halec_promises[handshake_url] ||= []
        end
    end

    class HALECUnavailable < Exception

    end
  end
end