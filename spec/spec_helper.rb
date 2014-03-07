require 'rspec'

require 'simplecov'

require_relative 'support/rspec-prof'
require_relative 'support/test_body_generator'
require_relative 'support/shared-proxy'

require_relative '../lib/tresor'

# spec_helper.rb
RSpec.configure do |config|
  # Disable 'should' for consistency
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include Tresor::TestBodyGenerator

  Tresor::Proxy::TresorProxy.logger.level = ::Logger::INFO
end