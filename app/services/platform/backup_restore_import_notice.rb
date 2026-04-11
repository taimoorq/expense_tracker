module Platform
  class BackupRestoreImportNotice
    def self.build(counts:)
      parts = []

      if counts[:planning_templates]
        template_counts = counts[:planning_templates]
        total_templates = template_counts.values.sum
        parts << "#{total_templates} recurring transaction#{'s' unless total_templates == 1}"
      end

      if counts[:budget_months]
        month_counts = counts[:budget_months]
        parts << "#{month_counts[:months]} month#{'s' unless month_counts[:months] == 1} and #{month_counts[:entries]} entr#{month_counts[:entries] == 1 ? 'y' : 'ies'}"
      end

      if counts[:accounts]
        account_counts = counts[:accounts]
        parts << "#{account_counts[:accounts]} account#{'s' unless account_counts[:accounts] == 1} and #{account_counts[:snapshots]} snapshot#{'s' unless account_counts[:snapshots] == 1}"
      end

      "Import complete: restored #{parts.join(', ')}."
    end
  end
end
