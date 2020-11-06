locals {
  namespace     = "datadotworld"
  name          = "nasa"
  stage         = "stg"
  region        = "us-east-1"
}

provider "aws" {
  region = local.region
}

module "vpc" {
  source     = "git::https://github.com/cloudposse/terraform-aws-vpc.git?ref=0.18.0"
  namespace  = local.namespace
  stage      = local.stage
  name       = local.name
  cidr_block = "172.16.0.0/16"
}

module "subnets" {
  source               = "git::https://github.com/cloudposse/terraform-aws-dynamic-subnets.git?ref=0.31.0"
  availability_zones   = ["us-east-1a"]
  namespace            = local.namespace
  stage                = local.stage
  name                 = local.name
  vpc_id               = module.vpc.vpc_id
  igw_id               = module.vpc.igw_id
  cidr_block           = module.vpc.vpc_cidr_block
  nat_gateway_enabled  = false
  nat_instance_enabled = false
}

module "s3_log_storage" {
  source        = "git::https://github.com/cloudposse/terraform-aws-s3-log-storage.git?ref=0.14.0"
  namespace     = local.namespace
  stage         = local.stage
  name          = local.name
  attributes    = ["logs"]
  force_destroy = true
}

module "aws_key_pair" {
  source              = "git::https://github.com/cloudposse/terraform-aws-key-pair.git?ref=0.15.0"
  namespace           = local.namespace
  stage               = local.stage
  name                = local.name
  attributes          = ["ssh", "key"]
  ssh_public_key_path = "/secrets"
  generate_ssh_key    = true
}

module "emr_cluster" {
  source                                         = "git::https://github.com/cloudposse/terraform-aws-emr-cluster.git?ref=0.14.0"
  namespace                                      = local.namespace
  stage                                          = local.stage
  name                                           = local.name
  master_allowed_security_groups                 = [module.vpc.vpc_default_security_group_id]
  slave_allowed_security_groups                  = [module.vpc.vpc_default_security_group_id]
  region                                         = local.region
  vpc_id                                         = module.vpc.vpc_id
  subnet_id                                      = module.subnets.private_subnet_ids[0]
  route_table_id                                 = module.subnets.private_route_table_ids[0]
  subnet_type                                    = "private"
  applications                                   = ["Spark"]
  core_instance_group_instance_type              = "r5.2xlarge"
  core_instance_group_instance_count             = 5
  core_instance_group_ebs_size                   = 10
  master_instance_group_instance_type            = "m4.large"
  master_instance_group_instance_count           = 1
  master_instance_group_ebs_size                 = 5
  log_uri                                        = format("s3://%s", module.s3_log_storage.bucket_id)
  key_name                                       = module.aws_key_pair.key_name
}