# Applied ~2 days before each exam month, removed after it (see docs/cost-report.md, optimisation O2).
#   terraform apply -var-file=terraform.tfvars -var-file=exam-month.tfvars
# Multi-AZ modify = standby is resized first, then a failover (~60-120 s), so run it outside exam hours.
db_instance_class = "db.t4g.large"
