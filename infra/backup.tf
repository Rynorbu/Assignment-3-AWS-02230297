# ---------------------------------------------------------------------------
# AWS Backup: daily snapshots (35 days) + monthly snapshots kept 5 years,
# encrypted with the project KMS key. Complements RDS PITR (5-minute RPO).
# ---------------------------------------------------------------------------
resource "aws_backup_vault" "main" {
  name          = "${local.name}-vault"
  kms_key_arn   = aws_kms_key.main.arn
  force_destroy = !var.db_deletion_protection
}

resource "aws_backup_plan" "main" {
  name = "${local.name}-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)"
    lifecycle {
      delete_after = 35
    }
    # Assignment 3: optional copy to the DR Region (removes "Region" as a data-loss single point of failure)
    dynamic "copy_action" {
      for_each = var.enable_dr_backup_copy ? [1] : []
      content {
        destination_vault_arn = aws_backup_vault.dr[0].arn
        lifecycle {
          delete_after = 7
        }
      }
    }
  }

  rule {
    rule_name         = "monthly-5-years"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 4 1 * ? *)"
    # Note (Assignment 3 cost finding): RDS snapshots do not support the cold-storage tier,
    # so cold_storage_after has no effect for the database; the 60 monthly snapshots stay warm
    # ($0.095/GB-month) and are costed that way in docs/cost-report.md.
    lifecycle {
      cold_storage_after = 90
      delete_after       = var.records_retention_days
    }
    dynamic "copy_action" {
      for_each = var.enable_dr_backup_copy ? [1] : []
      content {
        destination_vault_arn = aws_backup_vault.dr[0].arn
        lifecycle {
          delete_after = 90
        }
      }
    }
  }
}

# Vault in the DR Region (encrypted with that Region's AWS Backup managed key).
resource "aws_backup_vault" "dr" {
  count         = var.enable_dr_backup_copy ? 1 : 0
  provider      = aws.dr
  name          = "${local.name}-dr-vault"
  force_destroy = !var.db_deletion_protection
}

resource "aws_iam_role" "backup" {
  name = "${local.name}-backup"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "backup.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_selection" "db" {
  name         = "${local.name}-db"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [aws_db_instance.main.arn]
}
