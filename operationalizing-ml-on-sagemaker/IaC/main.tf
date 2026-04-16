data "aws_caller_identity" "current" {
  provider = aws.account1
}
data "aws_partition" "current" {
  provider = aws.account1
}
data "aws_region" "current" {
  provider = aws.account1
}

locals {
  partition = data.aws_partition.current.partition
}

module "aws_networking_base_vpc_layer_module" {
  providers = {
    aws.main = aws.account1
    aws.dns  = aws.dns
  }
  source               = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-networking-base-vpc-tgw"
  cidr_block           = var.vpc_base_cidr_block
  vpc_name             = var.vpc_name
  availability_zones   = var.availability_zones
  private_subnets      = var.subnet_private_cidr_blocks
  public_subnets       = var.subnet_public_cidr_blocks
  database_subnets     = var.subnet_database_cidr_blocks
  create_nat_gateway   = true
  enable_dns_hostnames = true
}

module "aws_networking_integration_vpc_layer_module" {
  providers = {
    aws.main = aws.account1
  }
  source           = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-networking-integration-vpc"
  vpc_workloads_id = module.aws_networking_base_vpc_layer_module.id
  gw_endpoints_services = [
    { type = "s3", route_tables = module.aws_networking_base_vpc_layer_module.private_route_table_id_list },
  ]
}

# Storage creation
module "aws_storage_landing_objects_s3_bucket_layer_module" {
  providers = {
    aws.main = aws.account1
  }
  source                = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-storage-objects-s3"
  bucket_name           = "${var.project}-machine-learning-tests"
  force_destroy         = true
  versioning            = "Disabled"
  object_lock_enabled   = false
  lifecycle_rules       = []
  is_kms_used           = false
  bucket_policy_enabled = false
  confidentiality       = "internal"
  integrity             = "tolerable"
}

module "sagemaker-notebook-instance" {
  providers = {
    aws.main = aws.account1
  }
  source = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-ml-environment-model-dev-compute-notebook"
  project = "udacity-nanodegree"
  vpc_id = module.aws_networking_base_vpc_layer_module.id
  private_subnet_id = module.aws_networking_base_vpc_layer_module.private_subnet_id_list[0]
  sagemaker_instance_name = "udacity-ml"
  sagemaker_instance_type = "ml.t3.medium"
  platform_identifier = "notebook-al2-v2"
  direct_internet_access = "Disabled"
  volume_size = 50
  target_buckets = [module.aws_storage_landing_objects_s3_bucket_layer_module.bucket_id]
  repo_url = "https://github.com/cjmunoz131/udacity-aws-ml-nanodegree.git"
  env_name = "ml-dev"
  python_version = "3.11"
}