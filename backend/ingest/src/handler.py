import json
import os
import boto3
from decimal import Decimal

from parsers import ofx_parser, csv_parser
from normalizer import normalize
from categorizer import categorize_batch

s3        = boto3.client("s3")
dynamodb  = boto3.resource("dynamodb")
sqs       = boto3.client("sqs")

table     = dynamodb.Table(os.environ["TRANSACTIONS_TABLE"])
queue_url = os.environ["TRANSACTIONS_QUEUE_URL"]
bucket    = os.environ["FILES_BUCKET"]


def download_from_s3(s3_key: str) -> str:
    """Baixa o arquivo do S3 e retorna o conteúdo como string."""
    response = s3.get_object(Bucket=bucket, Key=s3_key)
    raw_bytes = response["Body"].read()

    for encoding in ("utf-8", "latin-1", "utf-8-sig"):
        try:
            return raw_bytes.decode(encoding)
        except UnicodeDecodeError:
            continue

    raise ValueError(f"Não foi possível decodificar o arquivo: {s3_key}")


def save_transactions(transactions: list[dict], user_id: str) -> int:
    """
    Persiste transações no DynamoDB usando batch_writer.
    O batch_writer agrupa até 25 writes por request — muito mais
    eficiente que put_item() individual em loop.
    Retorna o número de transações salvas.
    """
    saved = 0

    with table.batch_writer() as batch:
        for txn in transactions:

            sk = f"TXN#{txn['bookingDate']}#{txn['transactionId']}"

            batch.put_item(Item={
                "PK":              f"USER#{user_id}",
                "SK":              sk,
                "transactionId":   txn["transactionId"],
                "externalId":      txn["externalId"],
                "bookingDate":     txn["bookingDate"],
                "description":     txn["description"],
                "category":        txn["category"],
                "creditDebitType": txn["creditDebitType"],
                "transactionType": txn["transactionType"],
                "status":          txn["status"],
                "amount":          Decimal(txn["amount"]["amount"]),
                "rawAmount":       Decimal(str(txn["rawAmount"])),
                "currency":        txn["amount"]["currency"],
            })
            saved += 1

    return saved


def publish_to_sqs(user_id: str, count: int) -> None:
    """
    Publica evento no SQS para acionar a Lambda de Insights.
    A Lambda de Insights vai recalcular os indicadores para este usuário.
    """
    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps({
            "user_id":            user_id,
            "transactions_count": count,
            "trigger":            "ingest_complete",
        }),
    )


def handler(event, context):
    """Entry point da Lambda."""
    print(f"[INFO] Evento recebido: {json.dumps(event)}")

    body = event if isinstance(event, dict) else json.loads(event.get("body", "{}"))

    user_id   = body.get("user_id")
    s3_key    = body.get("s3_key")
    file_type = body.get("file_type", "ofx").lower()
    bank      = body.get("bank", "nubank").lower()

    if not user_id or not s3_key:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "user_id e s3_key são obrigatórios"}),
        }

    try:
        print(f"[INFO] Baixando {s3_key} do S3")
        content = download_from_s3(s3_key)

        if file_type == "ofx":
            raw_transactions = ofx_parser.parse(content)
        elif file_type == "csv":
            raw_transactions = csv_parser.parse(content, bank=bank)
        else:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": f"file_type inválido: {file_type}"}),
            }

        print(f"[INFO] {len(raw_transactions)} transações extraídas do arquivo")

        normalized = normalize(raw_transactions, user_id)

        categorized = categorize_batch(normalized)

        saved = save_transactions(categorized, user_id)
        print(f"[INFO] {saved} transações salvas no DynamoDB")

        publish_to_sqs(user_id, saved)
        print(f"[INFO] Evento publicado no SQS para user {user_id}")

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "message":            "Extrato processado com sucesso",
                "transactions_saved": saved,
                "user_id":            user_id,
            }),
        }

    except Exception as e:
        print(f"[ERROR] Falha no processamento: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
        }