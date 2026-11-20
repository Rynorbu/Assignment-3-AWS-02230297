variable "project" {
  description = "Short project name used as a prefix for resources"
  type        = string
  default     = "exam-platform-a3" # Assignment 3: unique name, the shared class account already has an "exam-platform-prod" stack
}

variable "environment" {
  description = "Environment name (prod, dev)"
  type        = string
  default     = "prod"
}

variable "region" {
  description = "Primary AWS region"
  type        = string
  default     = "ap-southeast-1" # Assignment 3: Singapore
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "nat_gateway_count" {
  description = "NAT gateways. Assignment 3 default is 0: every VPC Lambda reaches AWS services through VPC endpoints (S3 gateway, SQS interface, Secrets Manager interface when needed), which saves ~$86/month in Singapore and removes the NAT as a failure point."
  type        = number
  default     = 0
  validation {
    condition     = contains([0, 1, 2], var.nat_gateway_count)
    error_message = "nat_gateway_count must be 0, 1 or 2."
  }
}

variable "db_instance_class" {
  description = "RDS instance class. Assignment 3: db.t4g.medium in normal months (covered by a 1-yr Reserved Instance), db.t4g.large in the two exam months (infra/exam-month.tfvars). db.t4g.micro is the Assignment 2 demo size used as the load-test baseline."
  type        = string
  default     = "db.t4g.medium"
}

variable "db_backup_retention_days" {
  description = "Automated backup + point-in-time-recovery window. Any value >= 1 gives the ~5 minute RPO (PITR); the length only sets how far back you can restore. AWS Free plan accounts must use 1."
  type        = number
  default     = 7
  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35
    error_message = "db_backup_retention_days must be between 1 and 35 (0 would disable backups and break the RPO)."
  }
}

variable "enable_rds_proxy" {
  description = "Connection pooling between Lambda and RDS (production design). AWS Free plan accounts cannot create RDS Proxy: set false and the Lambdas connect directly (TLS + RDS-managed secret)."
  type        = bool
  default     = true
}

variable "db_multi_az" {
  description = "Synchronous standby in a second AZ. Keep true (required to survive the loss of an AZ); set false only if the AWS account plan refuses it."
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Set true for real production. False so the assignment stack can be torn down."
  type        = bool
  default     = false
}

variable "records_retention_days" {
  description = "How long submissions and monthly DB backups are kept (5 years)"
  type        = number
  default     = 1825
}

variable "ses_sender_email" {
  description = "Verified SES sender address (a verification email is sent on first apply)"
  type        = string
}

variable "ses_test_recipients" {
  description = "While SES is in sandbox mode, every recipient must be verified. List test student/tutor emails here."
  type        = list(string)
  default     = []
}

variable "alarm_email" {
  description = "Email that receives CloudWatch alarm notifications (empty = no subscription)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Optional custom domain, e.g. exams.example.ac.uk. Leave empty to use the CloudFront domain."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for domain_name (required if domain_name is set)"
  type        = string
  default     = ""
}

variable "waf_rate_limit_per_ip" {
  description = "Requests per 5 minutes per IP (flood backstop). Assignment 3: raised from 20,000 after the load test showed 3,000 students behind one IP need ~46,000 per 5 min."
  type        = number
  default     = 150000
}

variable "waf_rate_limit_per_student" {
  description = "Requests per 5 minutes per sign-in token. A student autosaves 10 times per 5 min; 1,000 leaves room for page loads and retries."
  type        = number
  default     = 1000
}

variable "api_throttle_burst" {
  type    = number
  default = 5000
}

variable "api_throttle_rate" {
  type    = number
  default = 2000
}

variable "enable_cloudtrail" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention. Cut from 90 to 30 days in Assignment 3 (older logs are not needed once an exam is marked; CloudTrail keeps the audit trail)."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Assignment 3 additions
# ---------------------------------------------------------------------------
variable "api_reserved_concurrency" {
  description = "Reserved concurrency for the API Lambda. -1 = unreserved (uses the account pool). Without RDS Proxy (AWS Free plan) set it below the database max_connections so a traffic spike queues at API Gateway instead of exhausting PostgreSQL connections."
  type        = number
  default     = -1
}

variable "dr_region" {
  description = "Region that receives cross-Region copies of the backups (disaster recovery if Singapore is lost)."
  type        = string
  default     = "ap-south-1"
}

variable "enable_dr_backup_copy" {
  description = "Copy the daily and monthly AWS Backup recovery points to dr_region. Removes the 'single Region' data-loss risk for a few dollars a month."
  type        = bool
  default     = false
}

variable "enable_fis" {
  description = "Create the AWS Fault Injection Service experiment template used by failure test FT3 (network loss in one AZ)."
  type        = bool
  default     = false
}

variable "lambda_subnet_indexes" {
  description = "Which app subnets (0 = first AZ, 1 = second AZ) the VPC Lambdas use. Lambda does not health-check its subnets, so in failure test FT3 the recovery step is to remove that AZ here and apply (~2-4 minutes)."
  type        = list(number)
  default     = [0, 1]
  validation {
    condition     = length(var.lambda_subnet_indexes) > 0 && alltrue([for i in var.lambda_subnet_indexes : contains([0, 1], i)])
    error_message = "lambda_subnet_indexes must contain 0 and/or 1."
  }
}
