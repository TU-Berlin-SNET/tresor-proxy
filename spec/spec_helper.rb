require 'rspec'

require 'simplecov'

# spec_helper.rb
RSpec.configure do |config|
  # Disable 'should' for consistency
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end