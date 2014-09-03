module Tresor
  module Frontend
    extend ActiveSupport::Autoload

    # TODO Refactor out HTTP & TCTP modules for related handlers, like with ClaimSSO
    autoload :FrontendHandler
    autoload :HTTPRelayFrontendHandler
    autoload :HTTPEncryptingRelayFrontendHandler
    autoload :TCTPDiscoveryFrontendHandler
    autoload :TCTPHalecCreationFrontendHandler
    autoload :TCTPHandshakeFrontendHandler
    autoload :TresorProxyFrontendHandler

    autoload :ClaimSSO
  end
end