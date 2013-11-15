module Tresor
  module TCTP
    class HALECRegistry
      def initialize
        @halecs = {}
        @halec_promises = {}
        @tctp_cookies = {}
      end

      def promise_for(host, resource_url)
        handshake_url = Tresor::TCTP.handshake_url(host, resource_url)

        free_halecs = halecs(handshake_url)
        free_halec_promises = halec_promises(handshake_url)

        if free_halec_promises.count >= free_halecs.count
          raise HALECUnavailable.new
        else
          free_halec_promises[free_halec_promises.length] = HALECPromise.new(host, handshake_url, self)
        end
      end

      def return_halec_promise(promise)
        halec_promises(promise.handshake_url).delete(promise)
      end

      def get_tctp_cookie(host)
        @tctp_cookies[host]
      end

      def register_tctp_cookie(host, cookie)
        @tctp_cookies[host] = cookie
      end

      def register_halec(handshake_url, halec)
        halecs(handshake_url)[halec.url] = halec
      end

      class HALECPromise
        attr_accessor :host
        attr_accessor :handshake_url
        attr_accessor :halec_registry
        attr_accessor :promised_halec

        def initialize(host, handshake_url, halec_registry)
          @host = host
          @handshake_url = handshake_url
          @halec_registry = halec_registry
        end

        def redeem_halec(halec_url = nil)
          if halec_url
            @promised_halec = @halec_registry.halecs(@handshake_url)[halec_url]
          else
            @promised_halec = @halec_registry.halec_for(@host, @handshake_url)
          end
        end

        def return
          @halec_registry.halecs(@handshake_url)[@promised_halec.url] = @promised_halec

          @halec_registry.return_halec_promise(self)

          @promised_halec = nil
        end
      end

      def halec_for(host, resource_url)
        handshake_url = Tresor::TCTP.handshake_url(host, resource_url)

        free_halecs = halecs(handshake_url)

        if free_halecs.count == 0
          raise HALECUnavailable.new
        else
          free_halecs.shift[1]
        end
      end

      def halecs(handshake_url)
        @halecs[handshake_url] ||= {}
      end

      def halec_promises(handshake_url)
        @halec_promises[handshake_url] ||= []
      end
    end

    class HALECUnavailable < Exception

    end
  end
end