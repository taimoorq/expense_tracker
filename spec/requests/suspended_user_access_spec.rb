require "rails_helper"

RSpec.describe "Suspended user access", type: :request do
  let(:user) { create(:user, access_state: :suspended) }

  before do
    sign_in user
  end

  it "signs the user out on the next authenticated request" do
    get root_path

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq("Your access has been suspended. Contact an administrator for help.")
  end
end
