module AuthenticationHelpers
  def sign_in_as(user, password: "password123!")
    login_as(user, scope: :user)
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :system
  config.include Warden::Test::Helpers, type: :system

  config.before(:each, type: :system) do
    Warden.test_mode!
  end

  config.after(:each, type: :system) do
    Warden.test_reset!
  end
end
