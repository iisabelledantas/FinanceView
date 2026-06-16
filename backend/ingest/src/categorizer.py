"""
Categorização de transações por palavras-chave na descrição.
Abordagem simples e eficaz para o MVP — sem ML.

Cada categoria tem uma lista de keywords. A função percorre
as categorias em ordem de prioridade e retorna a primeira que bater.
"""

CATEGORY_RULES: list[tuple[str, list[str]]] = [
    ("salario",       ["salario", "salary", "pagamento de salario", "folha"]),
    ("alimentacao",   ["ifood", "rappi", "uber eats", "mcdonalds", "mc donalds",
                       "burger", "pizza", "restaurante", "lanchonete", "padaria",
                       "supermercado", "mercado", "pao de acucar", "carrefour",
                       "extra", "atacadao", "assai", "hortifruti"]),
    ("transporte",    ["uber", "99", "cabify", "taxi", "metrô", "metro",
                       "onibus", "passagem", "combustivel", "gasolina", "posto",
                       "estacionamento", "pedagio", "bilhete unico"]),
    ("moradia",       ["aluguel", "condominio", "iptu", "agua", "luz", "energia",
                       "gas", "internet", "telefone", "celular", "claro", "vivo",
                       "tim", "oi", "net", "gafisa", "mrv"]),
    ("saude",         ["farmacia", "drogaria", "droga", "unimed", "amil",
                       "bradesco saude", "sulamerica", "medico", "consulta",
                       "hospital", "clinica", "laboratorio", "exame", "drogasil",
                       "pacheco", "ultrafarma"]),
    ("educacao",      ["escola", "faculdade", "universidade", "curso", "udemy",
                       "alura", "coursera", "livro", "amazon", "saraiva",
                       "cultura", "mensalidade"]),
    ("lazer",         ["netflix", "spotify", "amazon prime", "disney", "hbo",
                       "cinema", "teatro", "show", "ingresso", "steam",
                       "playstation", "xbox", "jogos", "bar", "balada"]),
    ("vestuario",     ["renner", "riachuelo", "c&a", "hering", "zara", "h&m",
                       "shein", "roupa", "calcado", "sapato", "tenis"]),
    ("financeiro",    ["juros", "tarifa", "taxa", "iof", "ted", "doc", "pix",
                       "transferencia", "saque", "rendimento", "aplicacao",
                       "resgate", "investimento"]),
    ("outros",        []),  
]


def categorize(description: str) -> str:
    """
    Retorna a categoria de uma transação com base na descrição.
    Case-insensitive. Retorna 'outros' se nenhuma keyword bater.
    """
    desc_lower = description.lower()

    for category, keywords in CATEGORY_RULES:
        if not keywords:
            return category 
        if any(kw in desc_lower for kw in keywords):
            return category

    return "outros"


def categorize_batch(transactions: list[dict]) -> list[dict]:
    """Categoriza uma lista de transações in-place e retorna a lista."""
    for txn in transactions:
        txn["category"] = categorize(txn.get("description", ""))
    return transactions