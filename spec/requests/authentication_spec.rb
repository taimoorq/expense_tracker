require "rails_helper"

RSpec.describe "Authentication", type: :request do
  it "redirects guests to the sign in page" do
    get root_path

    expect(response).to redirect_to(new_user_session_path)
  end
end