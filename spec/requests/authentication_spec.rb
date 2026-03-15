require "rails_helper"

RSpec.describe "Authentication", type: :request do
  it "redirects guests to the sign in page" do
    get root_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not show turnstile when it is not configured" do
    get new_user_session_path

    expect(response.body).not_to include("data-controller=\"turnstile\"")
  end

  context "when turnstile is enabled" do
    before do
      allow(TurnstileVerifier).to receive(:enabled?).and_return(true)
      allow(TurnstileVerifier).to receive(:site_key).and_return("site-key")
    end

    it "renders the widget on the sign in page" do
      get new_user_session_path

      expect(response.body).to include("data-controller=\"turnstile\"")
      expect(response.body).to include("turnstile/v0/api.js?render=explicit")
    end

    it "blocks user sign in when verification fails" do
      user = create(:user)
      allow_any_instance_of(TurnstileVerifier).to receive(:success?).and_return(false)

      post user_session_path, params: {
        user: {
          email: user.email,
          password: user.password
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Please complete the verification challenge and try again.")
    end

    it "blocks sign up when verification fails" do
      allow_any_instance_of(TurnstileVerifier).to receive(:success?).and_return(false)

      expect do
        post user_registration_path, params: {
          user: {
            email: "new-user@example.com",
            password: "password123!",
            password_confirmation: "password123!"
          }
        }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Please complete the verification challenge and try again.")
    end
  end
end
