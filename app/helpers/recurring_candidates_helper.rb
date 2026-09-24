module RecurringCandidatesHelper
  def candidate_decision_fields(candidate)
    safe_join([
      hidden_field_tag(:expected_version, candidate[:decision]&.lock_version || -1, id: nil),
      hidden_field_tag(:evidence_digest, candidate[:evidence_digest], id: nil)
    ])
  end

  def candidate_template_token(template)
    "#{template.is_a?(Subscription) ? 'subscription' : 'monthly_bill'}:#{template.id}"
  end

  def candidate_template_edit_path(template)
    template.is_a?(Subscription) ? edit_subscription_planning_templates_path(template.id) : edit_monthly_bill_planning_templates_path(template.id)
  end

  def candidate_template_label(template)
    amount = template.is_a?(Subscription) ? template.amount : template.default_amount
    frequency = template.is_a?(Subscription) ? "Monthly" : template.billing_frequency.humanize
    [ template.name, template.model_name.human, number_to_currency(amount || 0), "#{frequency}, day #{template.due_day}", template.account_name.presence || "No account", template.active? ? nil : "Inactive" ].compact.join(" · ")
  end
end
