"""
Parser para arquivos OFX (Open Financial Exchange).
OFX é um formato semi-XML usado por Nubank, Itaú, Bradesco, BB, Inter, Santander, XP.

Estrutura relevante de um OFX:
    <STMTTRN>
        <TRNTYPE>DEBIT</TRNTYPE>
        <DTPOSTED>20240315120000[-3:BRT]</DTPOSTED>
        <TRNAMT>-45.90</TRNAMT>
        <FITID>20240315-001</FITID>
        <MEMO>IFOOD*PEDIDO123</MEMO>
    </STMTTRN>
"""

import re
from datetime import datetime


def parse_ofx_date(raw: str) -> str:
    """
    Converte data OFX para ISO 8601.
    OFX usa: 20240315120000[-3:BRT] ou 20240315
    Retorna: 2024-03-15
    """
    clean = re.sub(r'[\[\(].*', '', raw).strip()[:8]
    try:
        return datetime.strptime(clean, "%Y%m%d").strftime("%Y-%m-%d")
    except ValueError:
        return raw[:10]  


def parse(content: str) -> list[dict]:
    """
    Extrai transações de um arquivo OFX.
    Retorna lista de dicts com os campos brutos normalizados.
    """
    transactions = []

    blocks = re.findall(
        r'<STMTTRN>(.*?)</STMTTRN>',
        content,
        re.DOTALL | re.IGNORECASE
    )

    for block in blocks:
        def get_field(tag: str) -> str:
            """Extrai valor de uma tag OFX (sem fechamento): <TAG>valor"""
            match = re.search(
                rf'<{tag}>\s*([^\n<]+)',
                block,
                re.IGNORECASE
            )
            return match.group(1).strip() if match else ""

        txn_type = get_field("TRNTYPE").upper()
        amount_raw = get_field("TRNAMT").replace(",", ".")

        try:
            amount = float(amount_raw)
        except ValueError:
            continue  

        transactions.append({
            "external_id": get_field("FITID"),
            "date":        parse_ofx_date(get_field("DTPOSTED")),
            "amount":      amount,
            "description": get_field("MEMO") or get_field("NAME"),
            "type":        "DEBIT" if amount < 0 else "CREDIT",
            "raw_type":    txn_type,
        })

    return transactions