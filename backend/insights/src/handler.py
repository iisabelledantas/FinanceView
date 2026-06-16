import json
import os
from datetime import datetime, timezone

from more_itertools import bucket
import boto3
from boto3.dynamodb.conditions import Key

from health_score import calculate_health_score
from budget_checker import check_and_alert

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

transactions_table = dynamodb.Table(os.environ["TRANSACTIONS_TABLE"])
market_cache_table = dynamodb.Table(os.environ["MARKET_CACHE_TABLE"])
topic_arn          = os.environ["BUDGET_ALERTS_TOPIC_ARN"]
bucket             = os.environ["STATEMENTS_BUCKET"]


def get_current_period() -> str:
    """Retorna o período atual no formato YYYY-MM."""
    return datetime.now(timezone.utc).strftime("%Y-%m")


def fetch_transactions(user_id: str, period: str | None = None) -> list[dict]:
    """
    Busca transações do usuário no DynamoDB.
    Se period (YYYY-MM) for fornecido, filtra pelo mês.
    Usa begins_with na SK para aproveitar o índice nativo.
    """
    pk = f"USER#{user_id}"

    if period:
        
        key_condition = (
            Key("PK").eq(pk) &
            Key("SK").begins_with(f"TXN#{period}")
        )
    else:
        
        key_condition = (
            Key("PK").eq(pk) &
            Key("SK").begins_with("TXN#")
        )

    response = transactions_table.query(
        KeyConditionExpression=key_condition
    )
    return response.get("Items", [])


def fetch_ipca() -> float | None:
    """Lê o IPCA do cache DynamoDB. Retorna None se não disponível."""
    try:
        response = market_cache_table.get_item(Key={"PK": "IPCA"})
        item = response.get("Item")
        if item:
            return float(item["value"])
    except Exception as e:
        print(f"[WARN] Não foi possível ler IPCA do cache: {e}")
    return None


def process_insights(user_id: str, period: str | None = None) -> dict:
    """
    Orquestra o cálculo de insights para um usuário.
    Chamado tanto pelo trigger SQS quanto pelo API Gateway.
    """
    period = period or get_current_period()

    print(f"[INFO] Calculando insights para user={user_id}, period={period}")

    transactions = fetch_transactions(user_id, period)
    print(f"[INFO] {len(transactions)} transações encontradas")

    ipca    = fetch_ipca()
    health  = calculate_health_score(transactions, ipca)

    alerts = check_and_alert(
        table=transactions_table,
        user_id=user_id,
        expenses_by_category=health["expenses_by_category"],
        topic_arn=topic_arn,
    )

    return {
        "user_id": user_id,
        "period":  period,
        "health":  health,
        "alerts":  alerts,
        "market": {
            "ipca_monthly": ipca,
        },
    }


def generate_presigned_url(user_id: str, filename: str, file_type: str) -> dict:
    """
    Gera uma presigned URL para upload direto ao S3.
    O Flutter usa esta URL para fazer PUT do arquivo sem passar pela Lambda.

    Fluxo:
      1. Flutter chama POST /upload-url → recebe {upload_url, s3_key}
      2. Flutter faz PUT direto na upload_url com o arquivo
      3. Flutter chama POST /statements com o s3_key
    """
    s3_key = f"statements/{user_id}/{filename}"

    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket":      bucket,
            "Key":         s3_key,
            "ContentType": "application/octet-stream",
        },
        ExpiresIn=300, 
    )

    return {
        "upload_url": upload_url,
        "s3_key":     s3_key,
        "expires_in": 300,
    }

def handler(event, context):
    """Entry point — roteia por path quando vem do API Gateway."""
    print(f"[INFO] Path: {event.get('path')} | Method: {event.get('httpMethod')}")

    path   = event.get("path", "/statements")
    method = event.get("httpMethod", "POST")
    body   = {}

    if event.get("body"):
        try:
            body = json.loads(event["body"])
        except json.JSONDecodeError:
            body = {}

    claims  = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    user_id = body.get("user_id") or claims.get("sub") or body.get("user_id")
    
    if path == "/upload-url" and method == "POST":
        if not user_id:
            return {"statusCode": 401, "body": json.dumps({"error": "não autenticado"})}

        filename  = body.get("filename", "extrato.ofx")
        file_type = body.get("file_type", "ofx")
        result    = generate_presigned_url(user_id, filename, file_type)
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(result),
        }
    
    s3_key    = body.get("s3_key")
    file_type = body.get("file_type", "ofx").lower()
    bank      = body.get("bank", "nubank").lower()

    if not user_id or not s3_key:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "user_id e s3_key são obrigatórios"}),
        }

    try:
        content          = download_from_s3(s3_key)
        raw_transactions = ofx_parser.parse(content) if file_type == "ofx" else csv_parser.parse(content, bank=bank)
        normalized       = normalize(raw_transactions, user_id)
        categorized      = categorize_batch(normalized)
        saved            = save_transactions(categorized, user_id)
        publish_to_sqs(user_id, saved)

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
        print(f"[ERROR] {str(e)}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}