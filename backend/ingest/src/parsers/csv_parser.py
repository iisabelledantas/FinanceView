"""
Parsers para CSV — cada banco tem formato próprio.
Nubank e Inter são os mais comuns com exportação CSV.

CSV Nubank:
    Data,Descrição,Valor
    2024-03-15,IFOOD,-45.90

CSV Inter:
    Data Lançamento;Histórico;Descrição;Valor;Saldo
    15/03/2024;PIX RECEBIDO;Salário;5000,00;5000,00
"""

import csv
import io


def _parse_br_float(value: str) -> float:
    """Converte '1.234,56' ou '1234.56' para float."""
    clean = value.strip().replace("R$", "").strip()
    if "," in clean and "." in clean:
        clean = clean.replace(".", "").replace(",", ".")
    elif "," in clean:
        clean = clean.replace(",", ".")
    return float(clean)


def parse_nubank(content: str) -> list[dict]:
    """
    Parser para CSV do Nubank.
    Colunas: Data, Descrição, Valor
    Separador: vírgula. Encoding: UTF-8.
    """
    transactions = []
    reader = csv.DictReader(io.StringIO(content))

    for row in reader:
        try:
            amount = _parse_br_float(row.get("Valor", "0"))
            transactions.append({
                "external_id": f"nubank-{row.get('Data', '')}-{len(transactions)}",
                "date":        row.get("Data", "").strip(), 
                "amount":      amount,
                "description": row.get("Descrição", "").strip(),
                "type":        "DEBIT" if amount < 0 else "CREDIT",
                "raw_type":    "CSV_NUBANK",
            })
        except (ValueError, KeyError):
            continue

    return transactions


def parse_inter(content: str) -> list[dict]:
    """
    Parser para CSV do Inter.
    Colunas: Data Lançamento, Histórico, Descrição, Valor, Saldo
    Separador: ponto e vírgula. Encoding: UTF-8.
    """
    transactions = []
    reader = csv.DictReader(io.StringIO(content), delimiter=";")

    for row in reader:
        try:
            raw_value = row.get("Valor", "0")
            historico = row.get("Histórico", "").upper()
            amount = _parse_br_float(raw_value)

            if any(kw in historico for kw in ["DÉBITO", "PAGAMENTO", "SAQUE"]):
                amount = -abs(amount)

            raw_date = row.get("Data Lançamento", "").strip()
            if "/" in raw_date:
                parts = raw_date.split("/")
                date = f"{parts[2]}-{parts[1]}-{parts[0]}"
            else:
                date = raw_date

            transactions.append({
                "external_id": f"inter-{date}-{len(transactions)}",
                "date":        date,
                "amount":      amount,
                "description": row.get("Descrição", "").strip(),
                "type":        "DEBIT" if amount < 0 else "CREDIT",
                "raw_type":    "CSV_INTER",
            })
        except (ValueError, KeyError):
            continue

    return transactions


def parse(content: str, bank: str = "nubank") -> list[dict]:
    """Entry point — escolhe o parser pelo banco."""
    parsers = {
        "nubank": parse_nubank,
        "inter":  parse_inter,
    }
    return parsers.get(bank, parse_nubank)(content)