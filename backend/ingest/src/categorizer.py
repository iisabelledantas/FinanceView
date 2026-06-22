"""
Categorização local de transações.

O serviço combina regras determinísticas, sinais da transação e memória do
usuário. Não depende de APIs externas e mantém o comportamento previsível para
o fluxo de preview/importação.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from decimal import Decimal


SAVINGS_CATEGORY = "cofrinho_poupanca"
DEFAULT_CATEGORY = "outros"

CATEGORY_RULES: list[tuple[str, list[str]]] = [
    (
        SAVINGS_CATEGORY,
        [
            "aplicacao cofrinhos",
            "aplicacao cofrinho",
            "cofrinho",
            "poupanca",
            "poupança",
            "resgate cofrinho",
            "resgate poupanca",
            "resgate poupança",
        ],
    ),
    (
        "receita",
        [
            "salario",
            "salário",
            "salary",
            "pagamento de salario",
            "pagamento de salário",
            "folha",
            "pix recebido",
            "transferencia recebida",
            "transferência recebida",
            "recebimento",
            "deposito",
            "depósito",
        ],
    ),
    (
        "alimentacao",
        [
            "ifood",
            "rappi",
            "uber eats",
            "mcdonalds",
            "mc donalds",
            "burger",
            "pizza",
            "restaurante",
            "lanchonete",
            "padaria",
            "supermercado",
            "mercado",
            "pao de acucar",
            "pão de açúcar",
            "carrefour",
            "extra",
            "atacadao",
            "atacadão",
            "assai",
            "assaí",
            "hortifruti",
        ],
    ),
    (
        "transporte",
        [
            "uber",
            "99",
            "cabify",
            "taxi",
            "táxi",
            "metro",
            "metrô",
            "onibus",
            "ônibus",
            "passagem",
            "combustivel",
            "combustível",
            "gasolina",
            "posto",
            "estacionamento",
            "pedagio",
            "pedágio",
            "bilhete unico",
            "bilhete único",
        ],
    ),
    (
        "moradia",
        [
            "aluguel",
            "condominio",
            "condomínio",
            "iptu",
            "agua",
            "água",
            "luz",
            "energia",
            "gas",
            "gás",
            "internet",
            "telefone",
            "celular",
            "claro",
            "vivo",
            "tim",
            "oi",
            "net",
            "gafisa",
            "mrv",
        ],
    ),
    (
        "saude",
        [
            "farmacia",
            "farmácia",
            "drogaria",
            "droga",
            "unimed",
            "amil",
            "bradesco saude",
            "bradesco saúde",
            "sulamerica",
            "sulamérica",
            "medico",
            "médico",
            "consulta",
            "hospital",
            "clinica",
            "clínica",
            "laboratorio",
            "laboratório",
            "exame",
            "drogasil",
            "pacheco",
            "ultrafarma",
        ],
    ),
    (
        "educacao",
        [
            "escola",
            "faculdade",
            "universidade",
            "curso",
            "udemy",
            "alura",
            "coursera",
            "livro",
            "amazon",
            "saraiva",
            "cultura",
            "mensalidade",
        ],
    ),
    (
        "lazer",
        [
            "netflix",
            "spotify",
            "amazon prime",
            "disney",
            "hbo",
            "cinema",
            "teatro",
            "show",
            "ingresso",
            "steam",
            "playstation",
            "xbox",
            "jogos",
            "bar",
            "balada",
        ],
    ),
    (
        "vestuario",
        [
            "renner",
            "riachuelo",
            "c&a",
            "hering",
            "zara",
            "h&m",
            "shein",
            "roupa",
            "calcado",
            "calçado",
            "sapato",
            "tenis",
            "tênis",
        ],
    ),
    (
        "financeiro",
        [
            "juros",
            "tarifa",
            "taxa",
            "iof",
            "ted",
            "doc",
            "pix",
            "transferencia",
            "transferência",
            "saque",
            "rendimento",
            "aplicacao",
            "aplicação",
            "resgate",
            "investimento",
        ],
    ),
    (DEFAULT_CATEGORY, []),
]


@dataclass(frozen=True)
class CategorySuggestion:
    category: str
    source: str
    confidence: float
    signature: str


class LocalTransactionCategorizer:
    """Motor local de sugestão de categorias para transações financeiras."""

    def __init__(self, user_memory: dict[str, str] | None = None):
        self._user_memory = user_memory or {}

    def suggest(self, transaction: dict) -> CategorySuggestion:
        description = transaction.get("description", "")
        signature = category_memory_signature(description)

        if is_savings_description(description):
            return CategorySuggestion(
                category=SAVINGS_CATEGORY,
                source="local_rules",
                confidence=0.99,
                signature=signature,
            )

        if signature in self._user_memory:
            return CategorySuggestion(
                category=self._user_memory[signature],
                source="user_memory",
                confidence=0.98,
                signature=signature,
            )

        category, confidence = self._score_rules(transaction)
        return CategorySuggestion(
            category=category,
            source="local_rules" if category != DEFAULT_CATEGORY else "fallback",
            confidence=confidence,
            signature=signature,
        )

    def categorize_batch(self, transactions: list[dict]) -> list[dict]:
        for txn in transactions:
            suggestion = self.suggest(txn)
            txn["category"] = suggestion.category
            txn["suggestedCategory"] = suggestion.category
            txn["categorySuggestionSource"] = suggestion.source
            txn["categorySuggestionConfidence"] = round(suggestion.confidence, 2)
            txn["categoryMemorySignature"] = suggestion.signature
        return transactions

    def _score_rules(self, transaction: dict) -> tuple[str, float]:
        description = normalize_text(transaction.get("description", ""))
        amount = Decimal(str(transaction.get("rawAmount", 0)))
        txn_type = transaction.get("creditDebitType", "DEBIT")
        scores: dict[str, int] = {}

        for category, keywords in CATEGORY_RULES:
            if not keywords:
                continue
            for keyword in keywords:
                normalized_keyword = normalize_text(keyword)
                if normalized_keyword and normalized_keyword in description:
                    scores[category] = scores.get(category, 0) + len(
                        normalized_keyword.split()
                    ) + 2

        if txn_type == "CREDIT" or amount > 0:
            scores["receita"] = scores.get("receita", 0) + 1
            scores["financeiro"] = max(0, scores.get("financeiro", 0) - 1)
        else:
            scores["receita"] = max(0, scores.get("receita", 0) - 2)

        if "cofrinho" in description or "poupanca" in description:
            scores[SAVINGS_CATEGORY] = scores.get(SAVINGS_CATEGORY, 0) + 10

        if not scores:
            return DEFAULT_CATEGORY, 0.25

        category, score = max(scores.items(), key=lambda item: item[1])
        if score <= 0:
            return DEFAULT_CATEGORY, 0.25

        return category, min(0.95, 0.55 + score / 20)


def category_memory_signature(description: str) -> str:
    normalized = normalize_text(description)
    tokens = [
        token
        for token in normalized.split()
        if not token.isdigit() and len(token) > 1 and token not in STOPWORDS
    ]
    return " ".join(tokens[:6]) or normalized[:64] or "sem_descricao"


def is_savings_description(description: str) -> bool:
    normalized = normalize_text(description)
    return "cofrinho" in normalized or "poupanca" in normalized


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", str(value))
    normalized = "".join(char for char in normalized if not unicodedata.combining(char))
    normalized = normalized.casefold()
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized)
    return re.sub(r"\s+", " ", normalized).strip()


def categorize_batch(
    transactions: list[dict],
    user_memory: dict[str, str] | None = None,
) -> list[dict]:
    return LocalTransactionCategorizer(user_memory).categorize_batch(transactions)


STOPWORDS = {
    "compra",
    "pagamento",
    "pagto",
    "cartao",
    "cartaozinho",
    "credito",
    "debito",
    "pix",
    "ted",
    "doc",
    "brasil",
    "br",
}
