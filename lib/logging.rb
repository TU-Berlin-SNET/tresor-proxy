module Tresor
  [Backend, Connection, ConnectionPool, Backend::BackendHandler, Backend::BasicBackend, Backend::RelayingBackendHandler, TCTP::HALEC].each do |klass|
    klass.class_eval do
      def log
        TresorProxy.class_variable_get :@@logger
      end
    end
  end
end