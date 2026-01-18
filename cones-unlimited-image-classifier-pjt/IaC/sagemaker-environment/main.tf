module "sagemaker-domain-environment" {
  providers = {
    aws.main = aws.account1
    aws.dns  = aws.dns
  }
  source = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-ml-environment-model-dev-domain-sagemaker"
  project = "udacity-nanodegree"
  sagemaker_domain_auth_mode = "IAM"
  vpc_name = "ml-environment-vpc"
  sagemaker_domain_app_network_access_type = "VpcOnly"
  vpc_base_cidr_block = "10.0.0.0/16"
  subnet_public_cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
  subnet_private_cidr_blocks = ["10.0.3.0/24", "10.0.4.0/24"]
  kms_key_name = "kms-sagemaker-studio-key"
  availability_zones = ["a", "b"]
  enable_nat_gateway = true
  efs_retention_policy = "Delete"
}