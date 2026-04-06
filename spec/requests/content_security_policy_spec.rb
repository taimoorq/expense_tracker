require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  def csp_header
    response.headers.fetch("Content-Security-Policy")
  end

  it "sends a hardened CSP on public pages" do
    get new_user_session_path

    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(csp_header).to include("default-src 'self'")
      expect(csp_header).to include("base-uri 'self'")
      expect(csp_header).to include("frame-ancestors 'none'")
      expect(csp_header).to include("object-src 'none'")
      expect(csp_header).to include("script-src 'self' https://cdn.jsdelivr.net https://challenges.cloudflare.com")
      expect(csp_header).to include("script-src-attr 'none'")
      expect(csp_header).to include("style-src 'self' https:")
      expect(csp_header).to include("style-src-attr 'unsafe-inline'")
      expect(csp_header).to include("worker-src 'self'")
      expect(csp_header).to match(/script-src [^;]*'nonce-[^']+'/)
    end
  end

  it "keeps the same CSP protections on authenticated pages" do
    user = create(:user)
    sign_in user

    get settings_path

    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(csp_header).to include("form-action 'self'")
      expect(csp_header).to include("manifest-src 'self'")
      expect(csp_header).to include("connect-src 'self' https://challenges.cloudflare.com")
      expect(csp_header).to include("frame-src 'self' https://challenges.cloudflare.com")
      expect(csp_header).not_to match(/script-src[^;]*'unsafe-inline'/)
    end
  end
end
