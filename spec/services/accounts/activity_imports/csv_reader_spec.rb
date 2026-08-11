require "rails_helper"

RSpec.describe Accounts::ActivityImports::CsvReader do
  def with_uploaded_file(contents, filename: "activity.csv")
    file = Tempfile.new([ "account-activity", ".csv" ])
    file.binmode
    file.write(contents)
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: filename)

    yield upload
  ensure
    file&.close
    file&.unlink
  end

  it "reads a BOM-prefixed, headerless Best Buy Citibank tab export without losing its first row" do
    contents = "\uFEFF" + <<~TSV
      01/15/2026\t$-100.00\tSAMPLE CARD PAYMENT\tSAMPLE PAYMENT DETAIL
      01/14/2026\t$12.34\tSAMPLE STORE PURCHASE\tSAMPLE PURCHASE DETAIL
    TSV

    with_uploaded_file(contents, filename: "best-buy-activity.csv") do |upload|
      result = described_class.new(file: upload).call

      expect(result.ok).to be(true)
      expect(result.headers).to eq([ "Date", "Amount", "Description", "Details" ])
      expect(result.header_row_number).to eq(1)
      expect(result.rows.map(&:row_number)).to eq([ 1, 2 ])
      expect(result.rows.first.attributes).to include(
        "Date" => "01/15/2026",
        "Amount" => "$-100.00",
        "Description" => "SAMPLE CARD PAYMENT",
        "Details" => "SAMPLE PAYMENT DETAIL"
      )
      expect(result.metadata).to include(
        headerless: true,
        delimiter: "tab",
        source_format: "best_buy_citibank_headerless_tsv"
      )
    end
  end

  it "rejects a loosely similar headerless tab file when any row violates the format contract" do
    contents = <<~TSV
      01/15/2026\t$-100.00\tSAMPLE CARD PAYMENT\tSAMPLE PAYMENT DETAIL
      not-a-date\t$12.34\tSAMPLE STORE PURCHASE\tSAMPLE PURCHASE DETAIL
    TSV

    with_uploaded_file(contents) do |upload|
      result = described_class.new(file: upload).call

      expect(result.ok).to be(false)
      expect(result.error).to eq("Could not find a supported account activity CSV header.")
      expect(result.rows).to be_empty
    end
  end
end
