# Lambda function to update data in RDS database
module "lambda_function" {
  source        = "./modules/lambda"
  function_name = "lambda_function"
  role_arn      = module.carshub_media_update_function_iam_role.arn
  permissions   = []
  env_variables = {
    SECRET_NAME = module.carshub_db_credentials.name
    DB_HOST     = tostring(split(":", module.carshub_db.endpoint)[0])
    DB_NAME     = var.db_name
    REGION      = var.region
  }
  handler   = "lambda.lambda_handler"
  runtime   = "python3.12"
  s3_bucket = module.carshub_media_update_function_code.bucket
  s3_key    = "lambda.zip"
  layers    = [aws_lambda_layer_version.python_layer.arn]
}

# RDS Instance
module "carshub_db" {
  source                  = "./modules/rds"
  db_name                 = "carshub"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  multi_az                = true
  parameter_group_name    = "default.mysql8.0"
  username                = tostring(data.vault_generic_secret.rds.data["username"])
  password                = tostring(data.vault_generic_secret.rds.data["password"])
  subnet_group_name       = "carshub_rds_subnet_group"
  backup_retention_period = 7
  backup_window           = "03:00-05:00"
  subnet_group_ids = [
    module.carshub_public_subnets.subnets[0].id,
    module.carshub_public_subnets.subnets[1].id
  ]
  vpc_security_group_ids = [module.carshub_rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

# S3 buckets
module "carshub_media_bucket" {
  source      = "./modules/s3"
  bucket_name = "carshubmediabucket"
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
        lambda_function_arn = module.carshub_media_update_function.arn
        events              = ["s3:ObjectCreated:*"]
      }
    ]
  }
}