terraform {
  backend "s3" {
    bucket         = "redis-project-tfstate-bhoomi-2026"
    key            = "redis-project/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "redis-project-tf-lock"
    encrypt        = true
  }
}