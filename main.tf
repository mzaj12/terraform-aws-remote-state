locals {
  dynamo_hash_key           = "LockID"
  dynamo_enable_autoscaler  = false
  dynamo_attributes         = concat(module.label.attributes, ["lock"])
  bucket_versioning_enabled = true
  bucket_arn                = format("arn:aws:s3:::%s", module.label.id)
  bucket_attributes         = concat(module.label.attributes, [])
  bucket_kms_arn            = "*"
  bucket_kms_key            = var.state_kms == "master" ? "" : (var.state_kms == "auto" ? module.state_auth_kms_key.key_arn : var.state_kms)
  bucket_kms_attributes     = concat(module.label.attributes, ["key"])
  bukcet_policies = [
    data.aws_iam_policy_document.state_policy_root
  ]
  bukcet_kms_policies = [
    data.aws_iam_policy_document.state_kms_policy_root
  ]
}

data "aws_caller_identity" "provider" {}

module "label" {
  source  = "cloudposse/label/null"
  version = "0.16.0"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags
  attributes  = var.attributes
}

module "state_lock" {
  source  = "cloudposse/dynamodb/aws"
  version = "0.15.0"

  enabled           = var.lock
  namespace         = module.label.namespace
  environment       = module.label.environment
  name              = module.label.name
  tags              = module.label.tags
  attributes        = local.dynamo_attributes
  hash_key          = local.dynamo_hash_key
  enable_autoscaler = local.dynamo_enable_autoscaler
}

data "aws_iam_policy_document" "state_policy_root" {
  statement {
    sid    = "AllowManageRootStateBucket"
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      format("%s", local.bucket_arn),
      format("%s/*", local.bucket_arn)
    ]

    principals {
      type = "AWS"
      identifiers = [
        format("arn:aws:iam::%s:root", data.aws_caller_identity.provider.account_id)
      ]
    }
  }
}

# Merge multiple aws_iam_policy_document to one aws_iam_policy_document and set resource in all statement to s3 bucket arn
data "aws_iam_policy_document" "state_bucket_policy" {
  dynamic "statement" {
    for_each = flatten([
      for policy in concat(var.state_policies, local.bukcet_policies) : policy.statement
    ])

    content {
      sid         = lookup(statement.value, "sid", null)
      effect      = lookup(statement.value, "effect", null)
      actions     = lookup(statement.value, "actions", null)
      not_actions = lookup(statement.value, "not_actions", null)
      resources   = [local.bucket_arn]

      dynamic "principals" {
        for_each = toset([
          for principal in statement.value.principals : {
            for key, value in principal : key => value
          }
          if lookup(statement.value, "principals", null) != null
        ])

        content {
          identifiers = principals.value.identifiers
          type        = principals.value.type
        }
      }

      dynamic "not_principals" {
        for_each = toset([
          for not_principals in statement.value.not_principals : {
            for key, value in not_principals : key => value
          }
          if lookup(statement.value, "not_principals", null) != null
        ])

        content {
          identifiers = not_principals.value.identifiers
          type        = not_principals.value.type
        }
      }

      dynamic "condition" {
        for_each = toset([
          for condition in statement.value.condition : {
            for key, value in condition : key => value
          }
          if lookup(statement.value, "condition", null) != null
        ])

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

module "state_bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "0.8.0"

  enabled            = var.state
  namespace          = module.label.namespace
  environment        = module.label.environment
  name               = module.label.name
  tags               = module.label.tags
  attributes         = local.bucket_attributes
  versioning_enabled = local.bucket_versioning_enabled
  sse_algorithm      = var.state_sse
  kms_master_key_arn = local.bucket_kms_key
  policy             = data.aws_iam_policy_document.state_bucket_policy.json
}

data "aws_iam_policy_document" "state_kms_policy_root" {
  statement {
    sid    = "AllowManageRootStateBucketKMS"
    effect = "Allow"
    actions = [
      "kms:*",
    ]
    resources = [
      format("%s", local.bucket_arn),
      format("%s/*", local.bucket_arn)
    ]

    principals {
      type = "AWS"
      identifiers = [
        format("arn:aws:iam::%s:root", data.aws_caller_identity.provider.account_id)
      ]
    }
  }
}

# Merge multiple aws_iam_policy_document to one aws_iam_policy_document and set resource in all statement to kms arn
data "aws_iam_policy_document" "state_kms_policy" {
  dynamic "statement" {
    for_each = flatten([
      for policy in concat(var.state_kms_policies, local.bukcet_kms_policies) : policy.statement
    ])

    content {
      sid         = lookup(statement.value, "sid", null)
      effect      = lookup(statement.value, "effect", null)
      actions     = lookup(statement.value, "actions", null)
      not_actions = lookup(statement.value, "not_actions", null)
      resources   = [local.bucket_kms_arn]

      dynamic "principals" {
        for_each = toset([
          for principal in statement.value.principals : {
            for key, value in principal : key => value
          }
          if lookup(statement.value, "principals", null) != null
        ])

        content {
          identifiers = principals.value.identifiers
          type        = principals.value.type
        }
      }

      dynamic "not_principals" {
        for_each = toset([
          for not_principals in statement.value.not_principals : {
            for key, value in not_principals : key => value
          }
          if lookup(statement.value, "not_principals", null) != null
        ])

        content {
          identifiers = not_principals.value.identifiers
          type        = not_principals.value.type
        }
      }

      dynamic "condition" {
        for_each = toset([
          for condition in statement.value.condition : {
            for key, value in condition : key => value
          }
          if lookup(statement.value, "condition", null) != null
        ])

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

module "state_auth_kms_key" {
  source  = "cloudposse/kms-key/aws"
  version = "0.4.0"

  enabled     = var.state_kms == "auto" ? true : false
  namespace   = module.label.namespace
  environment = module.label.environment
  name        = module.label.name
  tags        = module.label.tags
  attributes  = local.bucket_kms_attributes
  policy      = data.aws_iam_policy_document.state_kms_policy.json
}