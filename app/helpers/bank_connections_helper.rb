module BankConnectionsHelper
  def bank_ledger_enabled?
    @workspace.target_reads_enabled? && @workspace.target_writes_enabled?
  end

  def bank_timestamp(value, workspace)
    value&.in_time_zone(workspace.time_zone)&.strftime("%b %-d, %Y at %-I:%M %p %Z")
  end

  def bank_account_connection_status(mapping)
    connection = mapping.bank_connection
    return "Disconnected · showing saved history" if connection.status == "disconnected"
    return "Ignored" if mapping.state == "ignored"
    return "Account unavailable" if mapping.state == "missing"
    return "Needs attention" if connection.status == "needs_attention" || mapping.error_message.present? || connection.error_message.present?
    return "Connecting" if connection.status == "connecting"

    connection.connected? ? "Connected" : "Reconnect needed"
  end
end
