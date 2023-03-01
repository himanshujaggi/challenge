######################### GCP Variables
variable "GOOGLE_PROJECT" {}
variable "GOOGLE_REGION" {}

variable "BOOT_DISK_SIZE" {
  type    = string
  default = "200"
}

variable "BOOT_DISK_TYPE" {
  type    = string
  default = "pd-standard"
}

variable "PERSISTENT_DISK_TYPE" {
  type    = string
  default = "pd-standard"
}