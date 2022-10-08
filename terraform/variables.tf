variable "database_name" {
  type = string
  sensitive = true
}
variable "database_password" {
  type = string
  sensitive = true
}
variable "database_user" {
  type = string
  sensitive = true
}
variable "region" {}
variable "shared_credentials_file" {}
variable "ami" {}
variable "AZ1" {}
variable "AZ2" {}
variable "AZ3" {}
variable "AZ4" {}
variable "instance_type" {}
variable "instance_class" {}
variable "USER" {
  type = string
  sensitive = true
}
variable "PUBLIC_KEY_PATH" {
  type = string
  sensitive = true
}
variable "PRIV_KEY_PATH" {
  type = string
  sensitive = true
}
