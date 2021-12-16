
terraform {
  required_version = ">= 0.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.60.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.3.0"
    }
  }
}

provider "aws" {
  region = data.aws_region.current.id
  alias  = "default"
}

terraform {
  backend "local" {
    path = "local_tf_state/terraform-main.tfstate"
  }
}

data "aws_region" "current" {}

locals {
  tenant      = "cust01"  # AWS account name or unique id for tenant
  environment = "preprod" # Environment area eg., preprod or prod
  zone        = "dev"     # Environment with in one sub_tenant or business unit

  kubernetes_version = "1.21"
  tags = tomap({ "created-by" = local.terraform_version })

  vpc_cidr     = "10.0.0.0/16"
  vpc_name     = join("-", [local.tenant, local.environment, local.zone, "vpc"])
  cluster_name = join("-", [local.tenant, local.environment, local.zone, "eks"])
  aws_availability_zones = ["us-east-1a", "us-east-1b"]

  # Bastion host or Cloud9 security group to get access to EKS Private API endpoint
  pc_security_group_id    = ["sg-0f625e6d0296c7db3"]
  
  terraform_version = "Terraform v0.14.11"

  # Enable=true Disable=false: this creates/destroys EKS, VPC-E, EKS Managed Node Group as needed
  # Setting create_eks=true creates new VPC. So create VPC Peering from calling VPC to new VPC, while EKS comes up
  # Setting all to false should remove but if issue with auth remval, run below to remove this module and t apply again 
  # t state rm module.aws-eks-accelerator-for-terraform.kubernetes_config_map.aws_auth[0]
  create_eks = false
  create_vpc_endpoints = false
  enable_managed_nodegroups = false
}

# ---------------------------------------------------------------------------------------------------------------------
# AWS VPC Module
# ---------------------------------------------------------------------------------------------------------------------
module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v3.2.0"

  name = local.vpc_name
  cidr = local.vpc_cidr
  azs  = local.aws_availability_zones

  # public_subnets  = [for k, v in data.aws_availability_zones.available.names : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.aws_availability_zones : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = false
  create_igw           = false
  enable_dns_hostnames = true

  # public_subnet_tags = {
  #   "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  #   "kubernetes.io/role/elb"                      = "1"
  # }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

#---------------------------------------------------------------
# VPC Endpoint Gateway
#---------------------------------------------------------------
module "vpc_endpoint_gateway" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "v3.2.0"

  create = local.create_vpc_endpoints
  vpc_id = module.aws_vpc.vpc_id

  endpoints = {
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      route_table_ids = flatten([
        module.aws_vpc.intra_route_table_ids,
        module.aws_vpc.private_route_table_ids])
      tags = { Name = "S3-VPC-Gateway" }
    },
  }
}

resource "aws_security_group" "vpc_endpoints" {
  count = local.create_vpc_endpoints == true ? 1 : 0
  name        = "vpc_endpoints_sg_${module.aws_vpc.vpc_id}"
  description = "Security group for all VPC Endpoints in ${module.aws_vpc.vpc_id}"
  vpc_id      = module.aws_vpc.vpc_id
  ingress {
    description      = "Ingress from EKS Private Subnets to VPC Endpoint"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = list(local.vpc_cidr)
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, {
    Project  = "EKS"
    Endpoint = "true"
  })
}

module "vpc_endpoints_gateway" {
  count = local.create_vpc_endpoints == true ? 1 : 0

  depends_on = [aws_security_group.vpc_endpoints]
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "v3.2.0"

  vpc_id             = module.aws_vpc.vpc_id
  security_group_ids = aws_security_group.vpc_endpoints == 0? []: [aws_security_group.vpc_endpoints[0].id]
  subnet_ids         = module.aws_vpc.private_subnets

  endpoints = {
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
    },
    logs = {
      service             = "logs"
      private_dns_enabled = true
    },
    autoscaling = {
      service             = "autoscaling"
      private_dns_enabled = true
    },
    sts = {
      service             = "sts"
      private_dns_enabled = true
    },
    elasticloadbalancing = {
      service             = "elasticloadbalancing"
      private_dns_enabled = true
    },
    ec2 = {
      service             = "ec2"
      private_dns_enabled = true
    },
    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
    },
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
    },
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
    },
    kms = {
      service             = "kms"
      private_dns_enabled = true
    },
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
    },   
  }
  tags =  merge(local.tags, {
    Project  = "EKS"
    Endpoint = "true"
  })
}

#---------------------------------------------------------------
# Example to consume aws-eks-accelerator-for-terraform module
#---------------------------------------------------------------
module "aws-eks-accelerator-for-terraform" {
  source            = "../../"
  tenant            = local.tenant
  environment       = local.environment
  zone              = local.zone
  terraform_version = local.terraform_version

  # EKS Cluster VPC and Subnet mandatory config
  vpc_id             = module.aws_vpc.vpc_id
  private_subnet_ids = module.aws_vpc.private_subnets
  pc_security_group_id = local.pc_security_group_id  

  # EKS CONTROL PLANE VARIABLES
  create_eks         = local.create_eks
  kubernetes_version = local.kubernetes_version

  #---------------------------------------------------------#
  # EKS WORKER NODE GROUPS
  # Define Node groups as map of maps object as shown below. Each node group creates the following
  #    1. New node group
  #    2. IAM role and policies for Node group
  #    3. Security Group for Node group (Optional)
  #    4. Launch Templates for Node group   (Optional)
  #---------------------------------------------------------#
  enable_managed_nodegroups = local.enable_managed_nodegroups
  managed_node_groups = {
    #---------------------------------------------------------#
    # ON-DEMAND Worker Group - Worker Group - 1
    #---------------------------------------------------------#
    mg_4 = {
      # 1> Node Group configuration - Part1
      node_group_name        = "managed-ondemand" # Max 40 characters for node group name
      create_launch_template = true               # false will use the default launch template
      launch_template_os     = "amazonlinux2eks"  # amazonlinux2eks or windows or bottlerocket
      public_ip              = false              # Use this to enable public IP for EC2 instances; only for public subnets used in launch templates ;
      pre_userdata           = <<-EOT
            yum install -y amazon-ssm-agent
            systemctl enable amazon-ssm-agent && systemctl start amazon-ssm-agent"
        EOT
      # 2> Node Group scaling configuration
      desired_size    = 1
      max_size        = 1
      min_size        = 1
      max_unavailable = 1 # or percentage = 20

      # 3> Node Group compute configuration
      ami_type       = "AL2_x86_64" # AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, CUSTOM
      capacity_type  = "ON_DEMAND"  # ON_DEMAND or SPOT
      instance_types = ["t3.medium"] # List of instances used only for SPOT type
      disk_size      = 50

      # 4> Node Group network configuration
      subnet_ids = module.aws_vpc.private_subnets # Define your private/public subnets list with comma seprated subnet_ids  = ['subnet1','subnet2','subnet3']

      k8s_taints = []

      k8s_labels = {
        Environment = "preprod"
        Zone        = "dev"
        WorkerType  = "ON_DEMAND"
      }
      additional_tags = {
        ExtraTag    = "m5x-on-demand"
        Name        = "m5x-on-demand"
        subnet_type = "private"
      }

      create_worker_security_group = false
    },
  } # END OF MANAGED NODE GROUPS

  #---------------------------------------------------------#
  # EKS SELF MANAGED WORKER NODE GROUPS
  #---------------------------------------------------------#
  enable_windows_support = false
  enable_self_managed_nodegroups = false

  self_managed_node_groups = {
    #---------------------------------------------------------#
    # ON-DEMAND Self Managed Worker Group - Worker Group - 1
    #---------------------------------------------------------#
    self_mg_4 = {
      node_group_name        = "self-managed-ondemand" # Name is used to create a dedicated IAM role for each node group and adds to AWS-AUTH config map
      create_launch_template = true
      launch_template_os     = "amazonlinux2eks"       # amazonlinux2eks  or bottlerocket or windows
      custom_ami_id          = "ami-0dfaa019a300f219c" # Bring your own custom AMI generated by Packer/ImageBuilder/Puppet etc.
      public_ip              = false                   # Enable only for public subnets
      pre_userdata           = <<-EOT
            yum install -y amazon-ssm-agent \
            systemctl enable amazon-ssm-agent && systemctl start amazon-ssm-agent \
        EOT

      disk_size     = 20
      instance_type = "m5.large"

      desired_size = 2
      max_size     = 10
      min_size     = 2

      capacity_type = "" # Optional Use this only for SPOT capacity as  capacity_type = "spot"

      k8s_labels = {
        Environment = "preprod"
        Zone        = "test"
        WorkerType  = "SELF_MANAGED_ON_DEMAND"
      }

      additional_tags = {
        ExtraTag    = "m5x-on-demand"
        Name        = "m5x-on-demand"
        subnet_type = "private"
      }

      subnet_ids = [] # Define your private/public subnets list with comma seprated subnet_ids  = ['subnet1','subnet2','subnet3']

      create_worker_security_group = false # Creates a dedicated sec group for this Node Group
    },
  } # END OF SELF MANAGED NODE GROUPS

  #---------------------------------------
  # METRICS SERVER HELM ADDON
  #---------------------------------------
  metrics_server_enable = false

  # Optional Map value
  metrics_server_helm_chart = {
    name       = "metrics-server"                                    # (Required) Release name.
    repository = "https://kubernetes-sigs.github.io/metrics-server/" # (Optional) Repository URL where to locate the requested chart.
    chart      = "metrics-server"                                    # (Required) Chart name to be installed.
    version    = "3.5.0"                                             # (Optional) Specify the exact chart version to install. If this is not specified, the latest version is installed.
    namespace  = "kube-system"                                       # (Optional) The namespace to install the release into. Defaults to default
    timeout    = "1200"                                              # (Optional)
    lint       = "true"                                              # (Optional)

    # (Optional) Example to show how to pass metrics-server-values.yaml
    values = [templatefile("${path.module}/k8s_addons/metrics-server-values.yaml", {
      operating_system = "linux"
    })]
  }

  #---------------------------------------
  # CLUSTER AUTOSCALER HELM ADDON
  #---------------------------------------
  cluster_autoscaler_enable = false

  # Optional Map value
  cluster_autoscaler_helm_chart = {
    name       = "cluster-autoscaler"                      # (Required) Release name.
    repository = "https://kubernetes.github.io/autoscaler" # (Optional) Repository URL where to locate the requested chart.
    chart      = "cluster-autoscaler"                      # (Required) Chart name to be installed.
    version    = "9.10.7"                                  # (Optional) Specify the exact chart version to install. If this is not specified, the latest version is installed.
    namespace  = "kube-system"                             # (Optional) The namespace to install the release into. Defaults to default
    timeout    = "1200"                                    # (Optional)
    lint       = "true"                                    # (Optional)

    # (Optional) Example to show how to pass metrics-server-values.yaml
    values = [templatefile("${path.module}/k8s_addons/cluster-autoscaler-vaues.yaml", {
      operating_system = "linux"
    })]
  }

  #---------------------------------------
  # ENABLE NGINX
  #---------------------------------------

  nginx_ingress_controller_enable = false
  # Optional nginx_helm_chart
  nginx_helm_chart = {
    name       = "ingress-nginx"
    chart      = "ingress-nginx"
    repository = "https://kubernetes.github.io/ingress-nginx"
    version    = "3.33.0"
    namespace  = "kube-system"
    values     = [templatefile("${path.module}/k8s_addons/nginx-values.yaml", {})]
  }

  #---------------------------------------
  # AWS-FOR-FLUENTBIT HELM ADDON
  #---------------------------------------
  aws_for_fluentbit_enable = false

  aws_for_fluentbit_helm_chart = {
    name                                      = "aws-for-fluent-bit"
    chart                                     = "aws-for-fluent-bit"
    repository                                = "https://aws.github.io/eks-charts"
    version                                   = "0.1.0"
    namespace                                 = "logging"
    aws_for_fluent_bit_cw_log_group           = "/${local.cluster_name}/worker-fluentbit-logs" # Optional
    aws_for_fluentbit_cwlog_retention_in_days = 90
    create_namespace                          = true
    values = [templatefile("${path.module}/k8s_addons/aws-for-fluentbit-values.yaml", {
      region                          = data.aws_region.current.name,
      aws_for_fluent_bit_cw_log_group = "/${local.cluster_name}/worker-fluentbit-logs"
    })]
    set = [
      {
        name  = "nodeSelector.kubernetes\\.io/os"
        value = "linux"
      }
    ]
  }

}
