module Tresor
  module TestBodyGenerator
    def test_body
      TestBodyGenerator.test_body
    end

    class << self
      def test_body
        @test_body ||= generate_test_body
      end

      def generate_test_body
        test_body_file = File.join(__dir__, 'test_body.txt')

        unless File.exists?(test_body_file)
          test_body = StringIO.new

          (1..100000).each do |x|
            test_body.write "#{x}:"
          end

          test_body_string = test_body.string

          IO.write test_body_file, test_body_string
        else
          test_body_string = IO.read test_body_file
        end

        test_body_string
      end
    end
  end
end