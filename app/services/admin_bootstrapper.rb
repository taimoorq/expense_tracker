class AdminBootstrapper
  Result = Struct.new(:admin_user, :status, keyword_init: true)

  def initialize(email: ENV["ADMIN_USER_EMAIL"].to_s.strip, password: ENV["ADMIN_USER_PASSWORD"].to_s)
    @admin_email = email
    @admin_password = password
  end

  def call
    validate_configuration!
    return Result.new(status: "skipped") if @admin_email.blank?

    admin_user = AdminUser.find_or_initialize_by(email: @admin_email)
    status = admin_user.new_record? ? "created" : "updated"

    if admin_user.new_record? || !admin_user.valid_password?(@admin_password)
      admin_user.password = @admin_password
      admin_user.password_confirmation = @admin_password
      admin_user.save!
    end

    Result.new(admin_user: admin_user, status: status)
  end

  private

  def validate_configuration!
    return unless @admin_email.present? ^ @admin_password.present?

    raise ArgumentError, "ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD must both be provided to bootstrap an admin user"
  end
end
