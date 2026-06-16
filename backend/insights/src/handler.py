import json
import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

from health_score import calculate_health_score
from budget_checker import check_and_alert, get_budgets

dynamodb = boto3.resource("dynamodb")

transactions_table = dynamodb.Table(os.environ["TRANSACTIONS_TABLE"])
market_cache_table = dynamodb.Table(os.environ["MARKET_CACHE_TABLE"])
topic_arn          = os.environ["BUDGET_ALERTS_TOPIC_ARN"]

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token",
    "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
    "Content-Type": "application/json",
}


def json_default(value):
    if isinstance(value, Decimal):
        return float(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def response(status_code: int, body: dict | list) -> dict:
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, default=json_default),
    }


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


def group_transactions_by_category(transactions: list[dict]) -> dict[str, list[dict]]:
    """Agrupa débitos por categoria para a tela de extratos."""
    grouped: dict[str, list[dict]] = {}

    for txn in transactions:
        if txn.get("creditDebitType") == "CREDIT":
            continue

        category = txn.get("category", "outros")
        grouped.setdefault(category, []).append({
            "transactionId": txn.get("transactionId", ""),
            "bookingDate": txn.get("bookingDate", ""),
            "description": txn.get("description", ""),
            "category": category,
            "creditDebitType": txn.get("creditDebitType", "DEBIT"),
            "transactionType": txn.get("transactionType", "UNKNOWN"),
            "amount": txn.get("amount", Decimal("0")),
            "rawAmount": txn.get("rawAmount", Decimal("0")),
            "currency": txn.get("currency", "BRL"),
        })

    for category in grouped:
        grouped[category].sort(
            key=lambda txn: txn.get("bookingDate", ""),
            reverse=True,
        )

    return grouped


def list_income_transactions(transactions: list[dict]) -> list[dict]:
    """Lista créditos para detalhamento de receitas na tela inicial."""
    income_transactions = []

    for txn in transactions:
        if txn.get("creditDebitType") != "CREDIT":
            continue

        income_transactions.append({
            "transactionId": txn.get("transactionId", ""),
            "bookingDate": txn.get("bookingDate", ""),
            "description": txn.get("description", ""),
            "category": txn.get("category", "outros"),
            "creditDebitType": txn.get("creditDebitType", "CREDIT"),
            "transactionType": txn.get("transactionType", "UNKNOWN"),
            "amount": txn.get("amount", Decimal("0")),
            "rawAmount": txn.get("rawAmount", Decimal("0")),
            "currency": txn.get("currency", "BRL"),
        })

    income_transactions.sort(
        key=lambda txn: txn.get("bookingDate", ""),
        reverse=True,
    )
    return income_transactions


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
        "transactions_by_category": group_transactions_by_category(transactions),
        "income_transactions": list_income_transactions(transactions),
        "alerts":  alerts,
        "market": {
            "ipca_monthly": ipca,
        },
    }


def save_budget(user_id: str, category: str, monthly_limit: float) -> dict:
    now = datetime.now(timezone.utc).isoformat()
    item = {
        "PK": f"USER#{user_id}",
        "SK": f"BUDGET#{category}",
        "category": category,
        "monthly_limit": Decimal(str(monthly_limit)),
        "current_spent": Decimal("0"),
        "usage_pct": Decimal("0"),
        "created_at": now,
        "updated_at": now,
    }
    transactions_table.put_item(Item=item)
    return item


def delete_transaction(user_id: str, transaction_id: str, booking_date: str) -> dict:
    sk = f"TXN#{booking_date}#{transaction_id}"

    response = transactions_table.delete_item(
        Key={
            "PK": f"USER#{user_id}",
            "SK": sk,
        },
        ReturnValues="ALL_OLD",
    )

    deleted = "Attributes" in response
    return {
        "deleted": deleted,
        "transactionId": transaction_id,
        "bookingDate": booking_date,
    }


def get_event_body(event: dict) -> dict:
    body = event.get("body")
    if not body:
        return {}
    if isinstance(body, dict):
        return body
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {}


def get_user_id(event: dict, body: dict) -> str | None:
    params = event.get("queryStringParameters") or {}
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    return params.get("user_id") or body.get("user_id") or claims.get("sub")

def handler(event, context):
    """Entry point — roteia por path quando vem do API Gateway."""
    print(f"[INFO] Path: {event.get('path')} | Method: {event.get('httpMethod')}")

    if "Records" in event:
        processed = 0
        for record in event["Records"]:
            body = json.loads(record.get("body", "{}"))
            user_id = body.get("user_id")
            if user_id:
                process_insights(user_id)
                processed += 1
        return {"processed": processed}

    path = event.get("path", "")
    method = event.get("httpMethod", "GET")

    if method == "OPTIONS":
        return response(200, {})

    body = get_event_body(event)
    params = event.get("queryStringParameters") or {}
    user_id = get_user_id(event, body)

    try:
        if path.endswith("/market") and method == "GET":
            return response(200, {"market": {"ipca_monthly": fetch_ipca()}})

        if not user_id:
            return response(401, {"error": "não autenticado"})

        if path.endswith("/insights") and method == "GET":
            return response(200, process_insights(user_id, params.get("period")))

        if path.endswith("/budgets") and method == "GET":
            return response(200, {"items": get_budgets(transactions_table, user_id)})

        if path.endswith("/budgets") and method == "POST":
            category = body.get("category")
            monthly_limit = body.get("monthly_limit")
            if not category or monthly_limit is None:
                return response(400, {"error": "category e monthly_limit são obrigatórios"})
            return response(201, save_budget(user_id, category, float(monthly_limit)))

        if path.endswith("/transactions") and method == "DELETE":
            transaction_id = body.get("transactionId")
            booking_date = body.get("bookingDate")
            if not transaction_id or not booking_date:
                return response(400, {"error": "transactionId e bookingDate são obrigatórios"})
            return response(200, delete_transaction(user_id, transaction_id, booking_date))

        return response(404, {"error": "rota não encontrada"})
    except Exception as e:
        print(f"[ERROR] {str(e)}")
        return response(500, {"error": str(e)})
