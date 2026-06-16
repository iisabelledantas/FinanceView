import hashlib
import re
from datetime import datetime

from preprocessors import pdf_text
from preprocessors.ocr import TextractOcrPreprocessor


DATE_PATTERN = re.compile(r"(?P<date>\d{2}/\d{2}/\d{4}|\d{4}-\d{2}-\d{2})")
DATE_AT_START_PATTERN = re.compile(r"^\s*(\d{2}/\d{2}/\d{4}|\d{4}-\d{2}-\d{2})\b")
MONEY_PATTERN = re.compile(
    r"(?P<sign>[-+])?\s*(?:R\$\s*)?(?P<amount>\d{1,3}(?:\.\d{3})*,\d{2}|\d+(?:[,.]\d{2}))"
)
MONEY_ONLY_PATTERN = re.compile(
    r"^\s*(?P<sign>[-+])?\s*(?:R\$\s*)?(?P<amount>\d{1,3}(?:\.\d{3})*,\d{2}|\d+(?:[,.]\d{2}))\s*$"
)

CREDIT_KEYWORDS = (
    "credito",
    "crédito",
    "recebido",
    "recebimento",
    "deposito",
    "depósito",
    "entrada",
    "salario",
    "salário",
)

DEBIT_KEYWORDS = (
    "debito",
    "débito",
    "pagamento",
    "compra",
    "saque",
    "tarifa",
    "taxa",
    "boleto",
    "transferencia enviada",
    "transferência enviada",
)

IGNORED_DESCRIPTIONS = (
    "saldo do dia",
)


def parse_from_s3(bucket: str, s3_key: str, bank: str = "generic", ocr=None) -> list[dict]:
    """Executa OCR no PDF e converte o texto em transações brutas."""
    preprocessor = ocr or TextractOcrPreprocessor()
    text = preprocessor.extract_text_from_s3_pdf(bucket, s3_key)
    return parse_text(text, bank=bank)


def parse_pdf_bytes(pdf_bytes: bytes, bank: str = "generic") -> list[dict]:
    """Extrai transações de PDFs que já possuem texto embutido."""
    text = pdf_text.extract_text(pdf_bytes)
    return parse_text(text, bank=bank)


def start_ocr_from_s3(bucket: str, s3_key: str, ocr=None) -> str:
    """Inicia OCR assíncrono no Textract e retorna o JobId."""
    preprocessor = ocr or TextractOcrPreprocessor()
    return preprocessor.start_text_detection(bucket, s3_key)


def parse_textract_job(job_id: str, bank: str = "generic", ocr=None) -> list[dict]:
    """Busca o resultado de um job Textract e converte em transações brutas."""
    preprocessor = ocr or TextractOcrPreprocessor()
    text = preprocessor.extract_text_from_job(job_id)
    return parse_text(text, bank=bank)


def parse_text(text: str, bank: str = "generic") -> list[dict]:
    """Extrai transações de texto OCR de extratos bancários em PDF."""
    transactions = []

    for line in _candidate_lines(text):
        transaction = _parse_line(line, bank=bank, index=len(transactions))
        if transaction:
            transactions.append(transaction)

    return transactions


def _candidate_lines(text: str) -> list[str]:
    lines = [_normalize_spaces(line) for line in text.splitlines()]
    candidates = []

    for index, line in enumerate(lines):
        if not DATE_AT_START_PATTERN.search(line):
            continue

        if MONEY_PATTERN.search(line):
            candidates.append(line)
            continue

        amount_line = _next_amount_line(lines, index + 1)
        if amount_line:
            candidates.append(f"{line} {amount_line}")

    return candidates


def _parse_line(line: str, bank: str, index: int) -> dict | None:
    date_match = DATE_PATTERN.search(line)
    amount_matches = list(MONEY_PATTERN.finditer(line))

    if not date_match or not amount_matches:
        return None

    amount_match = amount_matches[-1]
    date = _parse_date(date_match.group("date"))
    amount = _parse_amount(amount_match)
    description = _extract_description(line, date_match, amount_match)

    if not description or _should_ignore_description(description):
        return None

    amount = _apply_direction_from_text(amount, line)

    return {
        "external_id": _external_id(bank, date, line, index),
        "date": date,
        "amount": amount,
        "description": description,
        "type": "DEBIT" if amount < 0 else "CREDIT",
        "raw_type": "PDF_OCR",
    }


def _parse_date(raw_date: str) -> str:
    if "/" in raw_date:
        return datetime.strptime(raw_date, "%d/%m/%Y").strftime("%Y-%m-%d")
    return raw_date


def _parse_amount(match: re.Match) -> float:
    raw = match.group("amount").strip()

    if "," in raw and "." in raw:
        raw = raw.replace(".", "").replace(",", ".")
    elif "," in raw:
        raw = raw.replace(",", ".")

    amount = float(raw)
    if match.group("sign") == "-":
        return -abs(amount)
    return amount


def _extract_description(line: str, date_match: re.Match, amount_match: re.Match) -> str:
    description = line[date_match.end():amount_match.start()]
    description = re.sub(r"\b(R\$|BRL)\b", "", description, flags=re.IGNORECASE)
    return _normalize_spaces(description)


def _apply_direction_from_text(amount: float, line: str) -> float:
    normalized_line = line.casefold()

    if any(keyword in normalized_line for keyword in CREDIT_KEYWORDS):
        return abs(amount)

    if any(keyword in normalized_line for keyword in DEBIT_KEYWORDS):
        return -abs(amount)

    return amount


def _external_id(bank: str, date: str, line: str, index: int) -> str:
    digest = hashlib.sha256(line.encode("utf-8")).hexdigest()[:16]
    return f"{bank}-pdf-{date}-{index}-{digest}"


def _normalize_spaces(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _next_amount_line(lines: list[str], start_index: int) -> str | None:
    for line in lines[start_index:]:
        if not line:
            continue
        if DATE_AT_START_PATTERN.search(line):
            return None
        if MONEY_ONLY_PATTERN.fullmatch(line):
            return line
    return None


def _should_ignore_description(description: str) -> bool:
    normalized_description = description.casefold()
    return any(ignored in normalized_description for ignored in IGNORED_DESCRIPTIONS)
