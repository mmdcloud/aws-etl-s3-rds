# Lambda function to update media metadata in RDS database
module "lambda_function" {
  source        = "../../modules/lambda"
  function_name = "carshub_media_update_${var.env}"
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