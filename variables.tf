variable "service_name" {
  description = "The name of the service / project."
  type        = string
}

variable "main_branch" {
  description = "The name of the main git branch."
  type        = string
  default     = "main"
}

variable "compute_type" {
  description = "The compute type used by the build."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "tf_remote_state_bucket_arn" {
  description = "The bucket where TF remote states reside."
  type        = string
}

variable "ci_cd_artifacts_bucket_arn" {
  description = "The output bucket for TF artifacts. Each service will be given it's own key prefix."
  type        = string
}

variable "tf_ddb_state_lock_table" {
  description = "DynamoDB table used for terraform state lock"
  type        = string
}

variable "kms_ssm_key_arn" {
  description = "The KMS key arn used for SSM parameters."
  type        = string
}

variable "github_repo_url" {
  description = "The URL of the github repo to hook into."
  type        = string
}
