# frozen_string_literal: true

require "essenfont"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec do |c|
    c.syntax = :expect
  end
  config.disable_monkey_patching!
end
