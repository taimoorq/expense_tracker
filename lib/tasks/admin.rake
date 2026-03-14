namespace :admin do
  desc "Create or update the install-time admin user from ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD"
  task bootstrap: :environment do
    result = AdminBootstrapper.new.call

    if result.admin_user
      puts "Admin user #{result.status}: #{result.admin_user.email}"
    else
      puts "Admin bootstrap skipped: ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD not set"
    end
  end
end