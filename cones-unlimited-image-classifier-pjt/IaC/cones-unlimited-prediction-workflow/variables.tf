variable "project" {
  type        = string
  description = "Deployment project"
  default     = "cones"
}

variable "provisioner" {
  type        = string
  description = "Infraestructure provisioner"
  default     = "Terraform"
}

variable "owner" {
  type        = string
  description = "Project Owner"
  default     = "cjmunoz"
}

variable "org_unit" {
  type        = string
  description = "Organizational unit"
  default     = "products_crew"
}

variable "fin_unit" {
  type        = string
  description = "finance unit"
  default     = "vice_technology"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

########## LAMBDA IMAGE GENRERATOR FUNCTIONALITY VARIABLES ###############
variable "data_generator_functionality" {
  type        = string
  description = "Data generator functionality name"
  default     = "data-images-generator"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}

variable "data_images_classifier_functionality" {
  type        = string
  description = "Data images classifier functionality name"
  default     = "data-images-classifier"
}

variable "images_lowinference_filter_functionality" {
  type        = string
  description = "Data images low inference filter functionality name"
  default     = "images-lowinference-filter"
}

variable "functionality_sfn_inference_images_classifier" {
  type        = string
  description = "State machine functionality for inference images classifier"
  default     = "inference-images-classifier-wflow"
}

variable "integration_kms_key_name" {
  description = "value"
  type        = string
  default     = "integration-udacity"
}
