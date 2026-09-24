module Activity
  class SourceLabel
    def self.call(transaction)
      bank = transaction.provider_transactions.any?
      original = transaction.import_row_id ? "Statement CSV" : transaction.origin_kind_institution_import? ? "Imported" : transaction.origin_kind.humanize
      return original unless bank
      transaction.provider_transactions.all? { |source| source.resolution_kind == "existing" } ? "#{original} · SimpleFIN evidence" : "SimpleFIN"
    end
  end
end
