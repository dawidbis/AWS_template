# Szkielet: jedna lambda w Pythonie + rola + log group.
# Odpowiednik tego, co konsola tworzy przy "Create function" (rola <fn>-role-xxxx, log group).

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/lambda.zip"
}

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.prefix}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Log group tworzymy sami - inaczej lambda utworzy go przy 1. wywołaniu
# i zostanie po terraform destroy (bez retencji).
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
  function_name    = local.prefix
  role             = aws_iam_role.lambda.arn
  runtime          = "__RUNTIME__"
  architectures    = ["x86_64"]
  handler          = "app.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  depends_on = [aws_iam_role_policy_attachment.logs]
}
