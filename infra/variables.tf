variable "aws_region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo em todos os recursos"
  type        = string
  default     = "financeview"
}

variable "environment" {
  description = "Ambiente de deployment (dev, hom, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "hom", "prod"], var.environment)
    error_message = "O ambiente deve ser 'dev', 'hom' ou 'prod'."
  }
}