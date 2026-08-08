module Platform
  class BackupRestoreImportNotice
    def self.build(counts:)
      counts = counts.to_h.with_indifferent_access
      parts = []

      if counts[:planning_templates]
        template_counts = counts[:planning_templates]
        total_templates = template_counts.respond_to?(:values) ? template_counts.values.sum : template_counts.to_i
        parts << "#{total_templates} recurring transaction#{'s' unless total_templates == 1}"
      end

      if counts[:budget_months]
        month_counts = counts[:budget_months]
        parts << "#{month_counts[:months]} month#{'s' unless month_counts[:months] == 1} and #{month_counts[:entries]} entr#{month_counts[:entries] == 1 ? 'y' : 'ies'}"
      end


      if counts[:budget_periods] && !counts[:budget_months]
        parts << "#{counts[:budget_periods]} month#{'s' unless counts[:budget_periods] == 1} and #{counts[:budget_items].to_i} entr#{counts[:budget_items].to_i == 1 ? 'y' : 'ies'}"
      end

      if counts[:accounts]
        account_counts = counts[:accounts]
        if account_counts.respond_to?(:key?) && account_counts.key?(:accounts)
          parts << "#{account_counts[:accounts]} account#{'s' unless account_counts[:accounts] == 1} and #{account_counts[:snapshots]} snapshot#{'s' unless account_counts[:snapshots] == 1}"
        else
          parts << "#{account_counts.to_i} account#{'s' unless account_counts.to_i == 1} and #{counts[:balance_observations].to_i} balance observation#{'s' unless counts[:balance_observations].to_i == 1}"
        end
      end

      if counts[:account_activity]
        activity_counts = counts[:account_activity]
        parts << "#{activity_counts[:rows]} imported activity row#{'s' unless activity_counts[:rows] == 1}"
      end


      if counts[:import_rows] && !counts[:account_activity]
        parts << "#{counts[:import_rows]} imported activity row#{'s' unless counts[:import_rows] == 1}"
      end

      if counts[:preferences]
        preference_count = counts[:preferences].respond_to?(:key?) ? counts[:preferences][:preferences] : counts[:preferences].to_i
        parts << "#{preference_count} workflow preference#{'s' unless preference_count == 1}"
      end

      return "Import complete: no selected data was changed." if parts.empty?

      "Import complete: restored #{parts.join(', ')}."
    end
  end
end
