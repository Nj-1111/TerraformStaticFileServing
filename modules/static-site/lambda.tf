data "archive_file" "lambda" {
  count       = var.enable_cdn ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/invalidation.py"
  output_path = "${path.module}/lambda/invalidation.zip"
}

resource "aws_lambda_function" "invalidate" {
  count            = var.enable_cdn ? 1 : 0
  function_name    = "${var.project_name}-${var.environment}-invalidation"
  role             = aws_iam_role.lambda[0].arn
  filename         = data.archive_file.lambda[0].output_path
  source_code_hash = data.archive_file.lambda[0].output_base64sha256
  handler          = "invalidation.handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DISTRIBUTION_ID = aws_cloudfront_distribution.cdn[0].id
    }
  }
}

resource "aws_s3_bucket_notification" "invalidate" {
  count  = var.enable_cdn ? 1 : 0
  bucket = aws_s3_bucket.site.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.invalidate[0].arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3[0]]
}

resource "aws_lambda_permission" "allow_s3" {
  count         = var.enable_cdn ? 1 : 0
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invalidate[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.site.arn
}

