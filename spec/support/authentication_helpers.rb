module AuthenticationHelpers
  def sign_in_as(user, password: "password123!")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_button "Log in"
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :system
end