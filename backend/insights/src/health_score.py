from decimal import Decimal


SAVINGS_CATEGORIES = {"cofrinho", "cofrinho_poupanca"}


def calculate_health_score(transactions: list[dict], ipca_monthly: float | None) -> dict:
    """
    Calcula indicadores de saúde financeira a partir das transações.

    Retorna dict com:
    - total_income: soma dos créditos
    - total_expenses: soma dos débitos (valor positivo)
    - savings_rate: percentual poupado em relação à receita
    - expenses_by_category: gastos agrupados por categoria
    - savings_vs_ipca: comparação da poupança com a inflação
    - months: evolução mensal
    """
    total_income   = Decimal("0")
    total_expenses = Decimal("0")
    savings_balance = Decimal("0")
    by_category: dict[str, Decimal] = {}
    by_month: dict[str, dict]       = {}

    for txn in transactions:
        raw_amount = Decimal(str(txn.get("rawAmount", 0)))
        date       = txn.get("bookingDate", "")[:7] 
        category   = txn.get("category", "outros")
        txn_type   = txn.get("creditDebitType", "DEBIT")

        if is_savings_transaction(txn):
            savings_delta = cofrinho_delta(txn)
            savings_balance += savings_delta
            savings_to_account = -savings_delta if savings_delta < 0 else Decimal("0")
            total_income += savings_to_account

            if date:
                if date not in by_month:
                    by_month[date] = {"income": Decimal("0"), "expenses": Decimal("0")}
                by_month[date]["income"] += savings_to_account
                by_month[date]["savings_balance"] = (
                    by_month[date].get("savings_balance", Decimal("0"))
                    + savings_delta
                )
            continue

        if txn_type == "CREDIT":
            total_income += raw_amount
        else:
            abs_amount      = abs(raw_amount)
            total_expenses += abs_amount

            by_category[category] = by_category.get(category, Decimal("0")) + abs_amount

            if date not in by_month:
                by_month[date] = {"income": Decimal("0"), "expenses": Decimal("0")}
            by_month[date]["expenses"] += abs_amount

        if txn_type == "CREDIT" and date:
            if date not in by_month:
                by_month[date] = {"income": Decimal("0"), "expenses": Decimal("0")}
            by_month[date]["income"] += raw_amount

    savings_rate = 0.0
    if total_income > 0:
        saved        = total_income - total_expenses
        savings_rate = float(saved / total_income * 100)

    savings_vs_ipca = None
    if ipca_monthly is not None and savings_rate is not None:
        savings_vs_ipca = {
            "savings_rate_pct": round(savings_rate, 2),
            "ipca_monthly_pct": round(ipca_monthly, 4),
            "beating_inflation": savings_rate > ipca_monthly,
            "difference_pct":   round(savings_rate - ipca_monthly, 2),
        }

    return {
        "total_income":        float(total_income),
        "total_expenses":      float(total_expenses),
        "total_savings_movements": float(savings_balance),
        "total_savings_balance": float(savings_balance),
        "savings_rate":        round(savings_rate, 2),
        "expenses_by_category": {k: float(v) for k, v in by_category.items()},
        "monthly_evolution":   {
            month: {
                "income":   float(v["income"]),
                "expenses": float(v["expenses"]),
                "savings_movements": float(v.get("savings_balance", Decimal("0"))),
                "savings_balance": float(v.get("savings_balance", Decimal("0"))),
                "balance":  float(v["income"] - v["expenses"]),
            }
            for month, v in sorted(by_month.items())
        },
        "savings_vs_ipca": savings_vs_ipca,
    }


def is_savings_category(category: str) -> bool:
    return category in SAVINGS_CATEGORIES


def is_savings_transaction(txn: dict) -> bool:
    category = str(txn.get("category", ""))
    description = str(txn.get("description", "")).casefold()

    return is_savings_category(category) or "cofrinho" in description


def cofrinho_delta(txn: dict) -> Decimal:
    raw_amount = Decimal(str(txn.get("rawAmount", 0)))
    description = str(txn.get("description", "")).casefold()
    txn_type = txn.get("creditDebitType", "DEBIT")

    if "resgate" in description:
        return -abs(raw_amount)

    if "aplicacao" in description or "aplicação" in description:
        return abs(raw_amount)

    return -abs(raw_amount) if txn_type == "CREDIT" else abs(raw_amount)
