module Tresor
  module Backend
    extend ActiveSupport::Autoload

    autoload :BackendHandler
    autoload :BasicBackend
    autoload :RelayingBackendHandler
    autoload :TCTPDiscoveryBackendHandler
    autoload :TCTPEncryptToBackendHandler
    autoload :TCTPHandshakeBackendHandler
  end
end