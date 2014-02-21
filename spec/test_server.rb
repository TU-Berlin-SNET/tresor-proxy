require 'rack'

module Tresor
  class TestServer
    attr_accessor :current_post_body

    def call(env)
      case env['REQUEST_METHOD']
        when 'POST'
          input = StringIO.new
          until env['rack.input'].eof?
            input.write(env['rack.input'].read)
          end

          input_string = input.string

          IO.write('expected', current_post_body)
          IO.write('actual', input_string)

          if current_post_body.eql? input_string
            [ 200, {'Content-Type' => 'text/plain', 'Content-Length' => "#{input_string.length}"}, [input_string]]
          else
            [ 500, {'Content-Type' => 'text/plain', 'Content-Length' => '30'}, ['Did not receive correct string']]
          end
        else
          [ 200, {'Content-Type' => 'text/plain', 'Content-Length' => '7'}, ['Success']]
      end
    end
  end
end