require "selenium-webdriver"

Selenium::WebDriver.logger.level = :warn

Capybara.register_driver :managed_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--window-size=1400,1400")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")

  chrome_binary = ENV["CHROME_BIN"]
  driver_binary = ENV["CHROMEDRIVER_PATH"]

  options.binary = chrome_binary if chrome_binary.present?
  service = Selenium::WebDriver::Service.chrome(path: driver_binary) if driver_binary.present?

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :managed_headless_chrome
  end
end
