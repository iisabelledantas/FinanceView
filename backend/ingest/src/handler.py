import json
import os
import boto3
from decimal import Decimal

from parsers import ofx_parser, csv_parser, pdf_parser
from normalizer import normalize
from categorizer import CATEGORY_RULES, categorize_batch

s3        = boto3.client("s3")
dynamodb  = boto3.resource("dynamodb")
sqs       = boto3.client("sqs")
lambda_client = boto3.client("lambda")

table     = dynamodb.Table(os.environ["TRANSACTIONS_TABLE"])
queue_url = os.environ["TRANSACTIONS_QUEUE_URL"]
bucket    = os.environ["FILES_BUCKET"]

PDF_OCR_SOURCE = "financeview.ingest.pdf_ocr"
MAX_PDF_OCR_REINVOKES = int(os.environ.get("MAX_PDF_OCR_REINVOKES", "3"))
TEXTRACT_SUPPORTED_REGIONS = {
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "ap-south-1",
    "ap-northeast-2",
    "ap-southeast-1",
    "ap-southeast-2",
    "ca-central-1",
    "eu-central-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-south-2",
    "us-gov-east-1",
    "us-gov-west-1",
}

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Content-Type": "application/json",
}


def response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body),
    }


def download_bytes_from_s3(s3_key: str) -> bytes:
    """Baixa o arquivo do S3 e retorna o conteúdo em bytes."""
    response = s3.get_object(Bucket=bucket, Key=s3_key)
    return response["Body"].read()


def decode_file_content(raw_bytes: bytes, s3_key: str) -> str:
    """Decodifica conteúdo textual baixado do S3."""

    for encoding in ("utf-8", "latin-1", "utf-8-sig"):
        try:
            return raw_bytes.decode(encoding)
        except UnicodeDecodeError:
            continue

    raise ValueError(f"Não foi possível decodificar o arquivo: {s3_key}")


def download_from_s3(s3_key: str) -> str:
    """Baixa o arquivo textual do S3 e retorna o conteúdo como string."""
    return decode_file_content(download_bytes_from_s3(s3_key), s3_key)


def save_transactions(transactions: list[dict], user_id: str) -> int:
    """
    Persiste transações no DynamoDB usando batch_writer.
    O batch_writer agrupa até 25 writes por request — muito mais
    eficiente que put_item() individual em loop.
    Retorna o número de transações salvas.
    """
    saved = 0

    with table.batch_writer() as batch:
        for txn in transactions:

            sk = f"TXN#{txn['bookingDate']}#{txn['transactionId']}"

            batch.put_item(Item={
                "PK":              f"USER#{user_id}",
                "SK":              sk,
                "transactionId":   txn["transactionId"],
                "externalId":      txn["externalId"],
                "bookingDate":     txn["bookingDate"],
                "description":     txn["description"],
                "category":        txn["category"],
                "creditDebitType": txn["creditDebitType"],
                "transactionType": txn["transactionType"],
                "status":          txn["status"],
                "amount":          Decimal(txn["amount"]["amount"]),
                "rawAmount":       Decimal(str(txn["rawAmount"])),
                "currency":        txn["amount"]["currency"],
            })
            saved += 1

    return saved


def publish_to_sqs(user_id: str, count: int) -> None:
    """
    Publica evento no SQS para acionar a Lambda de Insights.
    A Lambda de Insights vai recalcular os indicadores para este usuário.
    """
    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps({
            "user_id":            user_id,
            "transactions_count": count,
            "trigger":            "ingest_complete",
        }),
    )


def process_raw_transactions(raw_transactions: list[dict], user_id: str) -> int:
    """Normaliza, categoriza, salva transações e publica evento de conclusão."""
    print(f"[INFO] {len(raw_transactions)} transações extraídas do arquivo")

    categorized = prepare_transactions_for_review(raw_transactions, user_id)

    saved = save_transactions(categorized, user_id)
    print(f"[INFO] {saved} transações salvas no DynamoDB")

    publish_to_sqs(user_id, saved)
    print(f"[INFO] Evento publicado no SQS para user {user_id}")

    return saved


def prepare_transactions_for_review(raw_transactions: list[dict], user_id: str) -> list[dict]:
    """Normaliza e categoriza transações sem persistir."""
    normalized = normalize(raw_transactions, user_id)
    return categorize_batch(normalized)


def extract_raw_transactions(s3_key: str, file_type: str, bank: str) -> tuple[list[dict], bool]:
    """
    Extrai transações brutas do arquivo.
    Retorna também se o processamento ficará assíncrono.
    """
    if file_type == "ofx":
        content = download_from_s3(s3_key)
        return ofx_parser.parse(content), False

    if file_type == "csv":
        content = download_from_s3(s3_key)
        return csv_parser.parse(content, bank=bank), False

    if file_type == "pdf":
        pdf_bytes = download_bytes_from_s3(s3_key)
        raw_transactions = pdf_parser.parse_pdf_bytes(pdf_bytes, bank=bank)
        if raw_transactions:
            return raw_transactions, False

        if not textract_is_available():
            raise ValueError(
                "Não foi possível extrair texto deste PDF e o OCR via Textract "
                "não está disponível na região AWS atual."
            )

        return [], True

    raise ValueError(f"file_type inválido: {file_type}")


def review_payload(transactions: list[dict], user_id: str) -> dict:
    return {
        "message": "Transações extraídas para revisão",
        "status": "review_required",
        "user_id": user_id,
        "transactions_count": len(transactions),
        "transactions": transactions,
        "categories": [category for category, _ in CATEGORY_RULES],
    }


def sanitize_reviewed_transactions(transactions: list[dict], user_id: str) -> list[dict]:
    """Aplica edições aprovadas pelo usuário antes de persistir."""
    sanitized = []

    for txn in transactions:
        credit_debit_type = txn.get("creditDebitType", "DEBIT")
        if credit_debit_type not in ("CREDIT", "DEBIT"):
            credit_debit_type = "DEBIT"

        amount = txn.get("amount", {})
        amount_value = Decimal(str(amount.get("amount", "0")))
        raw_amount = abs(Decimal(str(txn.get("rawAmount", amount_value))))

        if credit_debit_type == "DEBIT":
            raw_amount = -raw_amount

        sanitized.append({
            "transactionId": txn["transactionId"],
            "externalId": txn.get("externalId", ""),
            "userId": user_id,
            "bookingDate": txn.get("bookingDate", ""),
            "amount": {
                "amount": f"{abs(raw_amount):.2f}",
                "currency": amount.get("currency", "BRL"),
            },
            "creditDebitType": credit_debit_type,
            "transactionType": txn.get("transactionType", "UNKNOWN"),
            "description": txn.get("description", ""),
            "category": txn.get("category", "outros"),
            "status": txn.get("status", "COMPLETED"),
            "rawAmount": raw_amount,
        })

    return sanitized


def confirm_reviewed_transactions(transactions: list[dict], user_id: str) -> int:
    sanitized = sanitize_reviewed_transactions(transactions, user_id)
    saved = save_transactions(sanitized, user_id)
    print(f"[INFO] {saved} transações revisadas salvas no DynamoDB")
    publish_to_sqs(user_id, saved)
    print(f"[INFO] Evento publicado no SQS para user {user_id}")
    return saved


def invoke_pdf_ocr_worker(user_id: str, s3_key: str, bank: str, textract_job_id: str, attempt: int = 0) -> None:
    """Agenda continuação assíncrona da própria Lambda para PDFs."""
    lambda_client.invoke(
        FunctionName=os.environ["AWS_LAMBDA_FUNCTION_NAME"],
        InvocationType="Event",
        Payload=json.dumps({
            "source": PDF_OCR_SOURCE,
            "user_id": user_id,
            "s3_key": s3_key,
            "bank": bank,
            "textract_job_id": textract_job_id,
            "attempt": attempt,
        }).encode("utf-8"),
    )


def process_pdf_ocr_event(event: dict) -> dict:
    """Continuação assíncrona do processamento de PDF após iniciar Textract."""
    user_id = event["user_id"]
    s3_key = event["s3_key"]
    bank = event.get("bank", "generic")
    textract_job_id = event["textract_job_id"]
    attempt = int(event.get("attempt", 0))

    print(f"[INFO] Processando OCR PDF s3_key={s3_key} job={textract_job_id} attempt={attempt}")

    try:
        raw_transactions = pdf_parser.parse_textract_job(textract_job_id, bank=bank)
    except TimeoutError:
        if attempt >= MAX_PDF_OCR_REINVOKES:
            raise
        print(f"[INFO] OCR ainda em processamento; reagendando job={textract_job_id}")
        invoke_pdf_ocr_worker(user_id, s3_key, bank, textract_job_id, attempt=attempt + 1)
        return {"status": "requeued", "textract_job_id": textract_job_id}

    saved = process_raw_transactions(raw_transactions, user_id)
    return {
        "status": "processed",
        "transactions_saved": saved,
        "user_id": user_id,
        "s3_key": s3_key,
    }


def textract_is_available() -> bool:
    return os.environ.get("AWS_REGION") in TEXTRACT_SUPPORTED_REGIONS


def generate_presigned_url(user_id: str, filename: str, file_type: str) -> dict:
    s3_key = f"statements/{user_id}/{filename}"
    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": bucket,
            "Key": s3_key,
            "ContentType": "application/octet-stream",
        },
        ExpiresIn=300,
    )
    return {
        "upload_url": upload_url,
        "s3_key": s3_key,
        "file_type": file_type,
        "expires_in": 300,
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
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    return body.get("user_id") or claims.get("sub")


def handler(event, context):
    """Entry point da Lambda."""
    print(f"[INFO] Evento recebido: {json.dumps(event)}")

    if event.get("source") == PDF_OCR_SOURCE:
        return process_pdf_ocr_event(event)

    path = event.get("path", "")
    method = event.get("httpMethod", "POST")

    if method == "OPTIONS":
        return response(200, {})

    body = get_event_body(event)
    user_id = get_user_id(event, body)

    if path.endswith("/upload-url") and method == "POST":
        if not user_id:
            return response(401, {"error": "não autenticado"})
        filename = body.get("filename", "extrato.ofx")
        file_type = body.get("file_type", "ofx")
        return response(200, generate_presigned_url(user_id, filename, file_type))

    s3_key    = body.get("s3_key")
    file_type = body.get("file_type", "ofx").lower()
    bank      = body.get("bank", "nubank").lower()
    action    = body.get("action", "process").lower()

    if not user_id:
        return response(400, {"error": "user_id é obrigatório"})

    if action == "confirm":
        transactions = body.get("transactions", [])
        if not isinstance(transactions, list) or not transactions:
            return response(400, {"error": "transactions é obrigatório"})

        try:
            saved = confirm_reviewed_transactions(transactions, user_id)
            return response(
                200,
                {
                    "message": "Extrato confirmado com sucesso",
                    "transactions_saved": saved,
                    "user_id": user_id,
                },
            )
        except Exception as e:
            print(f"[ERROR] Falha na confirmação: {str(e)}")
            return response(500, {"error": str(e)})

    if not s3_key:
        return response(400, {"error": "s3_key é obrigatório"})

    try:
        print(f"[INFO] Baixando {s3_key} do S3")

        raw_transactions, is_async = extract_raw_transactions(s3_key, file_type, bank)

        if is_async and action == "preview":
            return response(
                422,
                {
                    "error": (
                        "Este PDF precisa de OCR assíncrono. A revisão prévia "
                        "está disponível para OFX, CSV e PDFs com texto embutido."
                    ),
                },
            )

        if is_async:
            textract_job_id = pdf_parser.start_ocr_from_s3(bucket, s3_key)
            invoke_pdf_ocr_worker(user_id, s3_key, bank, textract_job_id)
            return response(
                202,
                {
                    "message": "Extrato PDF recebido. O OCR será processado em segundo plano.",
                    "status": "processing",
                    "user_id": user_id,
                },
            )

        if action == "preview":
            reviewed = prepare_transactions_for_review(raw_transactions, user_id)
            return response(200, review_payload(reviewed, user_id))

        saved = process_raw_transactions(raw_transactions, user_id)

        return response(
            200,
            {
                "message":            "Extrato processado com sucesso",
                "transactions_saved": saved,
                "user_id":            user_id,
            },
        )

    except Exception as e:
        print(f"[ERROR] Falha no processamento: {str(e)}")
        return response(500, {"error": str(e)})
