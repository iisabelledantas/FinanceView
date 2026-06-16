import uuid


def normalize(raw_transactions: list[dict], user_id: str) -> list[dict]:
    """
    Converte lista de transações brutas para o schema OFB.
    Adiciona user_id e gera IDs únicos para cada transação.
    """
    normalized = []

    for raw in raw_transactions:
        amount = raw.get("amount", 0)

        normalized.append({
            "transactionId":   str(uuid.uuid4()),
            "externalId":      raw.get("external_id", ""),
            "userId":          user_id,

            "bookingDate":     raw.get("date", ""),
            "amount": {
                "amount":   f"{abs(amount):.2f}",  
                "currency": "BRL"
            },
            "creditDebitType": raw.get("type", "DEBIT"),
            "transactionType": raw.get("raw_type", "UNKNOWN"),
            "description":     raw.get("description", ""),
            "status":          "COMPLETED",

            "rawAmount":       amount, 
        })

    return normalized