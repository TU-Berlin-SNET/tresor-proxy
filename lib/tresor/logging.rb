module Tresor
  [Backend, Frontend, Frontend::FrontendHandler, Proxy::Connection, Proxy::ConnectionPool, Backend::BackendHandler, Backend::Backend, Backend::RelayingBackendHandler, Backend::BackendConnection, Rack::TCTP::HALEC, Rack::TCTP::ServerHALEC, Rack::TCTP::ClientHALEC].each do |klass|
    klass.class_eval do
      def log
        Tresor::Proxy::TresorProxy.class_variable_get :@@logger
      end

      def log_remote(severity, hash)
        begin
          log_hash = {
            'tresor-component' => 'Proxy',
            'logger' => self.class.name,
            'priority' => Logger::Severity.constants.find{ |name| Logger::Severity.const_get(name) == severity }
          }.merge(hash)

          proxy.logstash_logger.log severity, log_hash if proxy.logstash_logger
        rescue Exception => e
          puts e
        end
      end
    end
  end
end