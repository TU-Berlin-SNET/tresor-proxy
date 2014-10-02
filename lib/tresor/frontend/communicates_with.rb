module Tresor::Frontend::CommunicatesWith
  def communicates_with(name, config_variable)
    define_method "communicate_with_#{name}" do |connection, &block|
      http_symbol = "@#{name}_http".to_sym

      http = connection.proxy.instance_variable_get(http_symbol)

      unless http
        uri = URI(connection.proxy.send(config_variable))

        http = Net::HTTP.new(uri.host, uri.port)
        http.proxy_address = nil

        connection.proxy.instance_variable_set(http_symbol, http)
      end

      mutex_symbol = "@#{name}_http_mutex".to_sym

      mutex = connection.proxy.instance_variable_get(mutex_symbol)

      unless mutex
        mutex = Mutex.new

        connection.proxy.instance_variable_set(mutex_symbol, mutex)
      end

      mutex.synchronize do
        block.call(http)
      end
    end
  end
end