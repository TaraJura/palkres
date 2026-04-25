admin = User.find_or_initialize_by(email_address: "admin@palkres.cz")
admin.password = "palkres-admin-2026" if admin.new_record?
admin.role = :admin
admin.first_name = "Admin"
admin.last_name = "Palkres"
admin.save!
puts "Admin user: #{admin.email_address} (id=#{admin.id}, role=#{admin.role})"
