variable "project_name" {
  description = "Nome do projeto, usado como prefixo nos recursos"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}