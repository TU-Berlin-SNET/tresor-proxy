require 'rack'

module Tresor
  class SSOTestServer
    def call(env)
      [ 200, {'Content-Type' => 'text/plain', 'Content-Length' => '7'}, ['Success']]
    end
  end
end