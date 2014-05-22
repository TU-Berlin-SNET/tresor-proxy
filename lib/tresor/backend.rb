module Tresor
  module Backend
    extend ActiveSupport::Autoload

    autoload :BackendHandler
    autoload :Backend
    autoload :RelayingBackendHandler
    autoload :TCTPDiscoveryBackendHandler
    autoload :TCTPEncryptToBackendHandler
    autoload :TCTPHandshakeBackendHandler
  end
end