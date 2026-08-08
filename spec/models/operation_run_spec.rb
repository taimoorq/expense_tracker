require "rails_helper"

RSpec.describe OperationRun do
  it "keeps progress bounded and derives a stable percentage" do
    operation = build(:operation_run, progress_current: 3, progress_total: 4)

    expect(operation).to be_valid
    expect(operation.progress_percent).to eq(75)

    operation.progress_current = 5
    expect(operation).not_to be_valid
    expect(operation.errors[:progress_current]).to include("cannot exceed the progress total")
  end
end
