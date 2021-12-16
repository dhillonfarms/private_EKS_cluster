locals {
    account_id = data.aws_caller_identity.current.account_id
    name = "HD-EKS-Key-Dec21"
}

data "aws_iam_policy_document" "example" {

  statement {
    sid = "Enable IAM user permissions"
    effect = "Allow"
    actions = [
      "kms:*",
    ]
    principals {
        type = "AWS"
        identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    resources = [
      "*",
    ]
  }

  statement {
    sid = "Allow admin permissions for Key admins"
    effect = "Allow"
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource*",
      "kms:UntagResource*",
      "kms:ScheduleKeyDeletion*",
      "kms:CancelKeyDeletion*",
    ]
    principals {
        type = "AWS"
        identifiers = ["arn:aws:iam::${local.account_id}:role/Admin"]
    }

    resources = [
      "*",
    ]
  }

  # statement {
  #   sid = "Allow user permissions for Key users"
  #   effect = "Allow"
  #   actions = [
  #     "kms:Encrypt",
  #       "kms:Decrypt",
  #       "kms:ReEncrypt*",
  #       "kms:GenerateDataKey*",
  #       "kms:DescribeKey",
  #   ]
  #   principals {
  #       type = "AWS"
  #       identifiers = ["arn:aws:iam::${local.account_id}:root"]
  #   }
  #   resources = [
  #     "*",
  #   ]
  # }

  # statement {
  #   sid = "Allow user permissions for AWS services"
  #     effect = "Allow"
  #     actions = [
  #       "kms:CreateGrant",
  #     "kms:ListGrants",
  #     "kms:RevokeGrant"
  #     ]

  #   condition {
  #     test = "Bool" 
  #     variable = "kms:GrantIsForAWSResource" 
  #     values = [true]
  #   }

  #   principals {
  #       type = "AWS"
  #       identifiers = ["arn:aws:iam::${local.account_id}:root"]
  #   }

  #   resources = [
  #     "*",
  #   ]
  # }

  statement {
    sid = "Allow viaService1"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:DescribeKey"
      ]

    condition {
      test = "StringEquals" 
      variable = "kms:ViaService" 
      values = ["ec2.us-east-1.amazonaws.com"]
    }

    principals {
        type = "AWS"
        identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    resources = [
      "*",
    ]
  }
  statement {
    sid = "Enable Key to be used by Autoscaling"
      effect = "Allow"
      actions = [
         "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:Encrypt",
                "kms:DescribeKey",
                "kms:Decrypt"
      ]

    principals {
        type = "AWS"
        identifiers = ["arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }

    resources = [
      "*",
    ]
  }
  statement {
    sid = "Enable Key to be used for attachment with persistent resources"
      effect = "Allow"
      actions = [
         "kms:CreateGrant"
      ]

    principals {
        type = "AWS"
        identifiers = ["arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    condition {
      test = "Bool" 
      variable = "kms:GrantIsForAWSResource" 
      values = [true]
    }

    resources = [
      "*",
    ]
  }
}

resource "aws_kms_key" "hd-eks-key" {
  description             = "KMS key for EKS workers"
  is_enabled = true
  enable_key_rotation = true
  policy = data.aws_iam_policy_document.example.json
  tags = {
    Name = "hd-eks-kms-test-xcelerator"
  }
  depends_on = [
    aws_iam_role.managed_ng,
    aws_iam_instance_profile.managed_ng,
    aws_iam_role_policy_attachment.managed_ng_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.managed_ng_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.managed_ng_AmazonEC2ContainerRegistryReadOnly,
  ]
}