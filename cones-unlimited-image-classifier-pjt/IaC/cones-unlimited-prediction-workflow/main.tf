# ESTE MODULO CONTENDRA UNA ARQUITECTURA DE RECOLECCIÓN DE DATOS NEAR REAL-TIME CON PARTICIONAMIENTO DINAMICO
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
  sagemaker_bucket_name = "sagemaker-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
  sagemaker_bucket_arn  = "arn:aws:s3:::${local.sagemaker_bucket_name}"
}

module "aws_security_keys_integration_layer_module" {
  providers = {
    aws.main = aws.account1
  }
  source   = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-security-keys-kms"
  key_name = var.integration_kms_key_name
}

resource "aws_ssm_parameter" "olimpica_images_extensions" {
  provider = aws.account1
  name     = "/${var.project}/model-deployment-dict"
  type     = "String"
  value    = file("${path.root}/config/model-deployment-dict.json")
}

module "aws_app_compute_lambda_data-images-generator_layer_module" {
  providers = {
    aws.main = aws.account1
  }
  source             = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-app-compute-lambda"
  subnets_ids        = []
  security_group_ids = []
  lambda_name        = "${var.project}-${var.data_generator_functionality}"
  lambda_script      = ""
  lambda_runtime     = var.lambda_runtime
  description        = "functionality: data images generator for the ${var.project} project"
  source_code_path   = "./${path.root}/dev/lambdas"
  output_zip_path    = "./${path.root}/dev/artefacts/lambdas"
  lambda_layers      = null
  project            = var.project
  use_existing_role  = false
  add_custom_policy  = true
  custom_policy_path = "${path.root}/extra-policies/lambda"
  parameters_custom_policy_map = {
    region                = data.aws_region.current.name
    account_id            = data.aws_caller_identity.current.account_id
    bucket_s3_arn         = local.sagemaker_bucket_arn
  }
}

# module "aws_app_compute_lambda_layer_utils_layer_module" {
#   providers = {
#     aws.main = aws.account1
#   }
#   source                   = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-app-compute-layer-lambda"
#   layer_path_filename      = "./${path.root}/dev/layers/sagemaker/sagemaker.zip"
#   layer_name               = "sagemaker-layer"
#   compatibles_runtimes     = ["python3.11"]
#   compatible_architectures = ["arm64"]
# }

module "aws_app_compute_lambda_data-images-classifier_layer_module" {
  providers = {
    aws.main = aws.account1
  }
  source             = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-app-compute-lambda"
  subnets_ids        = []
  security_group_ids = []
  lambda_name        = "${var.project}-${var.data_images_classifier_functionality}"
  lambda_script      = ""
  lambda_runtime     = var.lambda_runtime
  description        = "functionality: data images classifier for the ${var.project} project"
  source_code_path   = "./${path.root}/dev/lambdas"
  output_zip_path    = "./${path.root}/dev/artefacts/lambdas"
  project            = var.project
  use_existing_role  = false
  add_custom_policy  = true
  custom_policy_path = "${path.root}/extra-policies/lambda"
  create_layers      = false
  lambda_layers_definitions = {}
  #lambda_layers                = [module.aws_app_compute_lambda_layer_utils_layer_module.lambda_layer_version_arn]
  lambda_layers = ["arn:aws:lambda:us-east-1:697682206292:layer:sagemaker-layer:2"]
  parameters_custom_policy_map = {
    region                = data.aws_region.current.name
    account_id            = data.aws_caller_identity.current.account_id
    ssm_parameter_prefix  = "${var.project}"
  }
  environment_variables = {
    MODEL_DEPLOYMENT_DICT = "/${var.project}/model-deployment-dict"
  }
}

module "aws_app_compute_lambda_images-lowinference-filter_layer_module" {
  providers = {
    aws.main = aws.account1
  }
  source             = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-app-compute-lambda"
  subnets_ids        = []
  security_group_ids = []
  lambda_name        = "${var.project}-${var.images_lowinference_filter_functionality}"
  lambda_script      = ""
  lambda_runtime     = var.lambda_runtime
  description        = "functionality: data images low inference filter for the ${var.project} project"
  source_code_path   = "./${path.root}/dev/lambdas"
  output_zip_path    = "./${path.root}/dev/artefacts/lambdas"
  lambda_layers      = null
  project            = var.project
  use_existing_role  = false
  add_custom_policy  = true
  custom_policy_path = "${path.root}/extra-policies/lambda"
  parameters_custom_policy_map = {
    region                = data.aws_region.current.name
    account_id            = data.aws_caller_identity.current.account_id
    bucket_s3_arn         = local.sagemaker_bucket_arn
  }
  environment_variables = {
    THRESHOLD = "0.75"
  }
}

module "aws_integration_workflow_inference_images_classifier_process_layer_module" {
  providers = {
    aws.main = aws.account1
  }
  source                 = "git@github.com:cjmunoz131/terraform_modules//modules/aws/aws-integration-workflow-process-step-function"
  create                 = true
  sfn_publish            = true
  source_definition_path = "${path.root}/state-machine-asls"
  sfn_state_machine_name = "sfn-${var.project}-${var.functionality_sfn_inference_images_classifier}-${terraform.workspace}"
  type                   = "STANDARD"
  vars_map = {
    data_images_generator_lambda_arn  = module.aws_app_compute_lambda_data-images-generator_layer_module.lambda_arn
    data_images_classifier_lambda_arn = module.aws_app_compute_lambda_data-images-classifier_layer_module.lambda_arn
    images_lowinference_filter_lambda_arn = module.aws_app_compute_lambda_images-lowinference-filter_layer_module.lambda_arn
  }
  tracing_enabled        = true
  custom_policy_path     = "${path.root}/extra-policies/step-function"
  create_terraform_style = false # aplica para la politica, quiero externa y formato json
  logging_configuration = {
    level                  = "ALL"
    include_execution_data = true
  }
  parameters_custom_policy_map = {
    data_images_generator_lambda_arn  = module.aws_app_compute_lambda_data-images-generator_layer_module.lambda_arn
    data_images_classifier_lambda_arn = module.aws_app_compute_lambda_data-images-classifier_layer_module.lambda_arn
    images_lowinference_filter_lambda_arn = module.aws_app_compute_lambda_images-lowinference-filter_layer_module.lambda_arn
  }
  cloudwatch_log_group_name              = "${var.project}-${var.functionality_sfn_inference_images_classifier}-${terraform.workspace}-SMLG"
  cloudwatch_log_group_retention_in_days = 7
  cloudwatch_log_group_kms_key_id        = module.aws_security_keys_integration_layer_module.kms_key_arn
  role_name                              = "${var.project}-${var.functionality_sfn_inference_images_classifier}-sfn-iar-${terraform.workspace}"
  depends_on                             = [aws_kms_key_policy.kms_key_access]
}