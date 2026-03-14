Capybara.register_driver :managed_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--window-size=1400,1400")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")

  original_path = ENV["PATH"]
  service = nil

  begin
    ENV["PATH"] = original_path.split(File::PATH_SEPARATOR).reject { |path| File.executable?(File.join(path, "chromedriver")) }.join(File::PATH_SEPARATOR)

    resolved_paths = Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome")
    service = Selenium::WebDriver::Service.chrome(path: resolved_paths.fetch("driver_path"))
    options.binary = resolved_paths["browser_path"] if resolved_paths["browser_path"]
  ensure
    ENV["PATH"] = original_path
  end

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
