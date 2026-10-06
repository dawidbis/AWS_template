variable "name" {
  description = "Nazwa labu; zasoby dostają prefiks __PREFIX__<name>"
  type        = string
  default     = "__NAME__"
}

variable "log_retention_days" {
  type    = number
  default = 3
}

locals {
  prefix = "__PREFIX__${var.name}"
}
