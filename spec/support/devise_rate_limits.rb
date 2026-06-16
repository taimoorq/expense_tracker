RSpec.configure do |config|
  config.before(:each) do
    DeviseRateLimited.clear_store
  end
end
