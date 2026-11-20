# Copy to terraform.tfvars (git-ignored) for local deploys. CI sets these via GitHub variables.
region              = "ap-southeast-1" # Assignment 3: Singapore
ses_sender_email    = "you@example.com"
ses_test_recipients = ["student1@example.com", "tutor1@example.com"]
alarm_email         = "you@example.com"

# Assignment 3 defaults (shown for clarity):
# nat_gateway_count = 0                # VPC endpoints only
# db_instance_class = "db.t4g.medium"  # normal months; see exam-month.tfvars
# log_retention_days = 30

# Optional custom domain:
# domain_name    = "exams.example.ac.uk"
# hosted_zone_id = "Z0123456789ABC"
