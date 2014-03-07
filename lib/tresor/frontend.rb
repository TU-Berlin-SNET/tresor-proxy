module Tresor
  module Frontend
    extend ActiveSupport::Autoload

    autoload :FrontendHandler
    autoload :HTTPRelayFrontendHandler
    autoload :HTTPEncryptingRelayFrontendHandler
    autoload :TCTPDiscoveryFrontendHandler
    autoload :TCTPHalecCreationFrontendHandler
    autoload :TCTPHandshakeFrontendHandler
  end
end