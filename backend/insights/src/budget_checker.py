import json
import os
import boto3
from decimal import Decimal
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
sns      = boto3.client("sns")


def get_budgets(table, user_id: str) -> list[dict]:
    """
    Busca todas as metas de orçamento do usuário.
    SK começa com "BUDGET#" — usamos begins_with para filtrar.
    """
    response = table.query(
        KeyConditionExpression=(
            Key("PK").eq(f"USER#{user_id}") &
            Key("SK").begins_with("BUDGET#")
        )
    )
    return response.get("Items", [])


def check_and_alert(
    table,
    user_id: str,
    expenses_by_category: dict[str, float],
    topic_arn: str,
) -> list[dict]:
    """
    Compara gastos reais com metas. Publica alerta no SNS
    para categorias que atingiram 80% do limite.

    Retorna lista de alertas disparados.
    """
    budgets = get_budgets(table, user_id)
    alerts  = []

    for budget in budgets:
        category      = budget["SK"].replace("BUDGET#", "")
        monthly_limit = float(budget.get("monthly_limit", 0))
        spent         = expenses_by_category.get(category, 0.0)

        if monthly_limit <= 0:
            continue

        usage_pct = (spent / monthly_limit) * 100

        table.update_item(
            Key={"PK": f"USER#{user_id}", "SK": f"BUDGET#{category}"},
            UpdateExpression="SET current_spent = :spent, usage_pct = :pct",
            ExpressionAttributeValues={
                ":spent": Decimal(str(round(spent, 2))),
                ":pct":   Decimal(str(round(usage_pct, 2))),
            },
        )

        if usage_pct >= 80:
            message = {
                "user_id":      user_id,
                "category":     category,
                "spent":        round(spent, 2),
                "limit":        monthly_limit,
                "usage_pct":    round(usage_pct, 2),
                "alert_type":   "BUDGET_80_PCT" if usage_pct < 100 else "BUDGET_EXCEEDED",
            }

            sns.publish(
                TopicArn=topic_arn,
                Message=json.dumps(message),
                Subject=f"FinanceView: alerta de orçamento — {category}",
                MessageAttributes={
                    "user_id": {
                        "DataType":    "String",
                        "StringValue": user_id,
                    }
                },
            )

            alerts.append(message)
            print(f"[INFO] Alerta SNS publicado: {category} em {usage_pct:.1f}%")

    return alerts