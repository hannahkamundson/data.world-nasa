locals {
  namespace               = "datadotworld"
  name                    = "nasa"
  stage                   = "stg"
  region                  = "us-east-1"
  hadoop_jar_step         = {
    jar                 = "command-runner.jar"
    main_class          = null
    args                = ["state-pusher-script"]
    properties          = {}

  }
  hadoop_debugging_step   = {
    name                  = "set up hadoop debugging"
    action_on_failure     = "TERMINATE_CLUSTER"
    hadoop_jar_step       = local.hadoop_jar_step
  }
  my_ip                   = var.my_ip
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
  enabled    = true
  enable_internet_gateway = true
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
  ssh_public_key_path = "./secrets"
  private_key_extension = ".pem"
  public_key_extension = "-public.pem"
  generate_ssh_key    = true
}

// This is dependent on the above. I haven't put the time into cleaning it up, so for now I just comment it out + run the other stuff + uncomment it and run it.
module "emr_cluster" {
  source                                         = "git::https://github.com/hannahkamundson/terraform-aws-emr-cluster.git?ref=7"
  namespace                                      = local.namespace
  release_label                                  = "emr-5.31.0"
  stage                                          = local.stage
  name                                           = local.name
  master_allowed_security_groups                 = [module.vpc.vpc_default_security_group_id]
  slave_allowed_security_groups                  = [module.vpc.vpc_default_security_group_id]
  region                                         = local.region
  vpc_id                                         = module.vpc.vpc_id
  subnet_id                                      = module.subnets.public_subnet_ids[0]
  route_table_id                                 = module.subnets.public_route_table_ids[0]
  subnet_type                                    = "public"
  applications                                   = ["Hadoop", "Spark"]
  core_instance_group_instance_type              = "r5.xlarge"
  core_instance_group_instance_count             = 3
  core_instance_group_ebs_size                   = 32
  master_instance_group_instance_type            = "m4.large"
  master_instance_group_instance_count           = 1
  master_instance_group_ebs_size                 = 32
  log_uri                                        = format("s3://%s", module.s3_log_storage.bucket_id)
  key_name                                       = module.aws_key_pair.key_name
  steps                                          = [local.hadoop_debugging_step]
}

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = module.emr_cluster.master_security_group_id
  cidr_blocks       = [local.my_ip]
}

resource "aws_security_group_rule" "spark_history" {
  type              = "ingress"
  from_port         = 18080
  to_port           = 18080
  protocol          = "tcp"
  security_group_id = module.emr_cluster.master_security_group_id
  cidr_blocks       = [local.my_ip]
}