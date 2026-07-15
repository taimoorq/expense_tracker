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

  it "uses one task heading and a distinct supporting showcase heading" do
    get new_user_session_path

    document = Nokogiri::HTML(response.body)

    expect(document.css("h1").map(&:text).map(&:strip)).to eq([ "Sign in to your workspace" ])
    expect(document.css(".ta-auth-showcase h2").text.strip).to eq("Secure access")
    expect(document.css(".ta-auth-showcase").text.scan("Sign in to your workspace")).to be_empty
  end

  it "saves the financial rhythm selected during sign up" do
    expect do
      post user_registration_path, params: {
        user: {
          email: "new-user@example.com",
          password: "password123!",
          password_confirmation: "password123!",
          financial_rhythm: "variable_income"
        }
      }
    end.to change(User, :count).by(1)

    expect(response).to redirect_to(root_path)
    expect(User.order(:created_at).last.financial_rhythm).to eq("variable_income")
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

  describe "Devise rate limiting" do
    before do
      allow_any_instance_of(TurnstileVerifier).to receive(:success?).and_return(true)
    end

    it "rate limits repeated user sign in attempts for the same email and IP" do
      user = create(:user)

      5.times do
        post user_session_path, params: {
          user: {
            email: user.email,
            password: "not-the-password"
          }
        }
      end

      post user_session_path, params: {
        user: {
          email: user.email,
          password: "not-the-password"
        }
      }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include(DeviseRateLimited::RATE_LIMIT_MESSAGE)
    end

    it "rate limits admin sign in attempts" do
      admin_user = create(:admin_user)

      5.times do
        post admin_user_session_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "not-the-password"
          }
        }
      end

      post admin_user_session_path, params: {
        admin_user: {
          email: admin_user.email,
          password: "not-the-password"
        }
      }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include(DeviseRateLimited::RATE_LIMIT_MESSAGE)
    end

    it "rate limits user registrations by IP" do
      5.times do |attempt|
        post user_registration_path, params: {
          user: {
            email: "rate-limited-#{attempt}@example.com",
            password: "short",
            password_confirmation: "different"
          }
        }
      end

      post user_registration_path, params: {
        user: {
          email: "rate-limited@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        }
      }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include(DeviseRateLimited::RATE_LIMIT_MESSAGE)
    end

    it "rate limits password reset requests for the same email and IP" do
      user = create(:user)

      5.times do
        post user_password_path, params: {
          user: {
            email: user.email
          }
        }
      end

      post user_password_path, params: {
        user: {
          email: user.email
        }
      }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include(DeviseRateLimited::RATE_LIMIT_MESSAGE)
    end
  end
end
