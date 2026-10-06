output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "invoke" {
  description = "Test z terminala (po . .\\env.ps1)"
  value       = "lambda-invoke ${aws_lambda_function.this.function_name} events/event.json"
}
