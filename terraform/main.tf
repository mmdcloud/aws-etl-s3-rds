# Registering vault provider
data "vault_generic_secret" "rds" {
  path = "secret/rds"
}

# VPC Configuration
module "vpc" {
  source                = "../../modules/vpc/vpc"
  vpc_name              = "vpc"
  vpc_cidr_block        = "10.0.0.0/16"
  enable_dns_hostnames  = true
  enable_dns_support    = true
  internet_gateway_name = "vpc_igw"
}

# Public Subnets
module "public_subnets" {
  source = "../../modules/vpc/subnets"
  name   = "public subnet"
  subnets = [
    {
      subnet = "10.0.1.0/24"
      az     = "us-east-1a"
    },
    {
      subnet = "10.0.2.0/24"
      az     = "us-east-1b"
    },
    {
      subnet = "10.0.3.0/24"
      az     = "us-east-1c"
    }
  ]
  vpc_id                  = module.vpc.vpc_id
  map_public_ip_on_launch = true
}

# Private Subnets
module "private_subnets" {
  source = "../../modules/vpc/subnets"
  name   = "private subnet"
  subnets = [
    {
      subnet = "10.0.6.0/24"
      az     = "us-east-1d"
    },
    {
      subnet = "10.0.5.0/24"
      az     = "us-east-1e"
    },
    {
      subnet = "10.0.4.0/24"
      az     = "us-east-1f"
    }
  ]
  vpc_id                  = module.vpc.vpc_id
  map_public_ip_on_launch = false
}

# Public Route Table
module "public_rt" {
  source  = "../../modules/vpc/route_tables"
  name    = "public route table"
  subnets = module.public_subnets.subnets[*]
  routes = [
    {
      cidr_block     = "0.0.0.0/0"
      gateway_id     = module.vpc.igw_id
      nat_gateway_id = ""
    }
  ]
  vpc_id = module.vpc.vpc_id
}

# Private Route Table
module "private_rt" {
  source  = "../../modules/vpc/route_tables"
  name    = "public route table"
  subnets = module.private_subnets.subnets[*]
  routes = []
  vpc_id = module.vpc.vpc_id
}

# Secrets Manager
module "db_credentials" {
  source                  = "../../modules/secrets-manager"
  name                    = "rds_secrets_${var.env}"
  description             = "rds_secrets_${var.env}"
  recovery_window_in_days = 0
  secret_string = jsonencode({
    username = tostring(data.vault_generic_secret.rds.data["username"])
    password = tostring(data.vault_generic_secret.rds.data["password"])
  })
}

# Lambda Layer for storing dependencies
resource "aws_lambda_layer_version" "python_layer" {
  filename            = "../../files/python.zip"
  layer_name          = "psycopg2_layer"
  compatible_runtimes = ["python3.12"]
}

# Lambda function to update data in RDS database
module "lambda_function" {
  source        = "./modules/lambda"
  function_name = "lambda_function"
  role_arn      = module.carshub_media_update_function_iam_role.arn
  permissions   = []
  env_variables = {}
  handler   = "lambda.lambda_handler"
  runtime   = "python3.12"
  s3_bucket = module.carshub_media_update_function_code.bucket
  s3_key    = "lambda.zip"
  layers    = [aws_lambda_layer_version.python_layer.arn]
}

# RDS Instance
module "db" {
  source                  = "./modules/rds"
  db_name                 = "db"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  multi_az                = true
  parameter_group_name    = "default.mysql8.0"
  username                = tostring(data.vault_generic_secret.rds.data["username"])
  password                = tostring(data.vault_generic_secret.rds.data["password"])
  subnet_group_name       = "rds_subnet_group"
  backup_retention_period = 7
  backup_window           = "03:00-05:00"
  subnet_group_ids = [
    module.carshub_public_subnets.subnets[0].id,
    module.carshub_public_subnets.subnets[1].id,
    module.carshub_public_subnets.subnets[2].id
  ]
  vpc_security_group_ids = [module.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

# Destination S3 Bucket
module "destination_bucket" {
  source      = "./modules/s3"
  bucket_name = "etldestinationbucketmadmax"
  objects = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue = []
    lambda_function = [
      {
        lambda_function_arn = module.lambda_function.arn
        events              = ["s3:ObjectCreated:*"]
      }
    ]
  }
}