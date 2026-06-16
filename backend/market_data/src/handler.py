import json
import os
import time
import urllib.request
import urllib.error
import boto3
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["MARKET_CACHE_TABLE"])


CACHE_TTL_SECONDS = 15 * 60


def fetch_bcb_indicator(series_code: int) -> float | None:
    """
    Busca o último valor de uma série temporal do Banco Central do Brasil.
    Documentação: https://dadosabertos.bcb.gov.br/dataset/taxas-de-juros-selic

    series_code 11  → SELIC (taxa diária)
    series_code 433 → IPCA (variação mensal)
    """
    url = (
        f"https://api.bcb.gov.br/dados/serie/bcdata.sgs.{series_code}"
        f"/dados/ultimos/1?formato=json"
    )
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            data = json.loads(response.read())
            return float(data[0]["valor"].replace(",", "."))
    except (urllib.error.URLError, KeyError, IndexError, ValueError) as e:
        print(f"[WARN] BCB série {series_code} falhou: {e}")
        return None


def fetch_exchange_rates() -> dict | None:
    """
    Busca cotações USD e EUR da AwesomeAPI.
    Retorna dict com as duas moedas ou None em caso de falha.
    Documentação: https://docs.awesomeapi.com.br/api-de-moedas
    """
    url = "https://economia.awesomeapi.com.br/json/last/USD-BRL,EUR-BRL"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            data = json.loads(response.read())
            return {
                "USD": float(data["USDBRL"]["bid"]),
                "EUR": float(data["EURBRL"]["bid"]),
            }
    except (urllib.error.URLError, KeyError, ValueError) as e:
        print(f"[WARN] AwesomeAPI falhou: {e}")
        return None


def write_to_cache(key: str, value: float | dict) -> None:
    """
    Grava um indicador no DynamoDB com TTL de 15 minutos.
    O DynamoDB deleta automaticamente o item após expires_at.

    Usamos Decimal para valores numéricos porque o DynamoDB
    não aceita float nativo do Python — apenas Decimal.
    """
    expires_at = int(time.time()) + CACHE_TTL_SECONDS

    if isinstance(value, dict):
        item_value = {k: Decimal(str(v)) for k, v in value.items()}
    else:
        item_value = Decimal(str(value))

    table.put_item(
        Item={
            "PK": key,
            "value": item_value,
            "updated_at": int(time.time()),
            "expires_at": expires_at,  
        }
    )
    print(f"[INFO] Cache gravado: {key} = {value} (TTL: {CACHE_TTL_SECONDS}s)")


def handler(event, context):
    """
    Entry point da Lambda. Chamado pelo EventBridge a cada 15 minutos.
    Retorna um resumo do que foi atualizado para facilitar debugging nos logs.
    """
    results = {}

    selic = fetch_bcb_indicator(11)
    if selic is not None:
        write_to_cache("SELIC", selic)
        results["SELIC"] = selic

    ipca = fetch_bcb_indicator(433)
    if ipca is not None:
        write_to_cache("IPCA", ipca)
        results["IPCA"] = ipca

    rates = fetch_exchange_rates()
    if rates is not None:
        write_to_cache("EXCHANGE_RATES", rates)
        results["EXCHANGE_RATES"] = rates

    print(f"[INFO] Market data atualizado: {json.dumps(results)}")

    return {
        "statusCode": 200,
        "updated": list(results.keys()),
        "timestamp": int(time.time()),
    }