# Roadmapa labów – serverless pod DAM (Bynder + pipeline AV)

Każdy lab: konsola → NOTES.md → sprzątanie → Terraform (→ SAM). Nazwa w nawiasie = `new-lab <nazwa>`.

| # | Lab | Serwisy | Czego uczy w kontekście DAM |
|---|---|---|---|
| 1 | Upload trigger (`s3-trigger`) | S3, Lambda, S3 event notification | upload pliku → lambda czyta metadane obiektu (key, size, content-type); `aws_lambda_permission` |
| 2 | Kolejka z DLQ (`sqs-buffer`) | SQS, DLQ, Lambda event source mapping | buforowanie uploadów, retry, `ReportBatchItemFailures` |
| 3 | Pipeline AV (`av-pipeline`) | S3 (incoming / clean / quarantine), EventBridge, Lambda, SNS | „skan” (np. wykrywanie pliku testowego EICAR) → przeniesienie do clean albo quarantine + alert. Potem porównaj z **GuardDuty Malware Protection for S3** |
| 4 | Orkiestracja (`scan-sfn`) | Step Functions, Lambda | scan → rendition → publish jako state machine, retry/catch, obsługa „infected” |
| 5 | Metadane assetów (`asset-meta`) | DynamoDB, Lambda | status assetu (uploaded/scanning/clean/infected), single-table, condition expressions |
| 6 | Webhook z Byndera (`bynder-webhook`) | API Gateway HTTP API (lub SNS), Lambda, SQS | odbiór zdarzeń asset created/updated; walidacja, szybkie 200 + praca asynchroniczna. Sprawdź w docs Byndera format webhooków (SNS subscription confirm) |
| 7 | Sekrety i API Byndera (`bynder-api`) | Secrets Manager / SSM Parameter Store, Lambda | token Byndera poza kodem, wywołania API z lambdy, timeouty |
| 8 | Obserwowalność (`observability`) | CloudWatch Logs Insights, alarmy, X-Ray, Powertools | logi strukturalne, metryki, alarm na DLQ |
| 9 | Terraform dla zespołu (`tf-modules`) | S3 backend + `use_lockfile`, moduły, workspaces/env | struktura jak w pracy; remote state |

Testy: `moto` (mock S3/SQS/DynamoDB w pytest), `sam local invoke` z eventami z `sam local generate-event s3 put`.
