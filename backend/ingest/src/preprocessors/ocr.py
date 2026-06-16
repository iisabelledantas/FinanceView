import os
import time


class TextractOcrPreprocessor:
    """Extrai texto de PDFs armazenados no S3 usando Amazon Textract."""

    def __init__(self, client=None, poll_interval_seconds: float | None = None, max_attempts: int | None = None):
        if client is None:
            import boto3

            client = boto3.client("textract")

        self.client = client
        self.poll_interval_seconds = poll_interval_seconds or float(
            os.environ.get("TEXTRACT_POLL_INTERVAL_SECONDS", "2")
        )
        self.max_attempts = max_attempts or int(os.environ.get("TEXTRACT_MAX_ATTEMPTS", "25"))

    def extract_text_from_s3_pdf(self, bucket: str, key: str) -> str:
        job_id = self.start_text_detection(bucket, key)
        return self.extract_text_from_job(job_id)

    def start_text_detection(self, bucket: str, key: str) -> str:
        response = self.client.start_document_text_detection(
            DocumentLocation={
                "S3Object": {
                    "Bucket": bucket,
                    "Name": key,
                }
            }
        )
        return response["JobId"]

    def extract_text_from_job(self, job_id: str) -> str:
        blocks = self._wait_for_blocks(job_id)
        return self.text_from_blocks(blocks)

    @staticmethod
    def text_from_blocks(blocks: list[dict]) -> str:
        lines = [
            block["Text"]
            for block in blocks
            if block.get("BlockType") == "LINE" and block.get("Text")
        ]
        return "\n".join(lines)

    def _wait_for_blocks(self, job_id: str) -> list[dict]:
        next_token = None

        for _ in range(self.max_attempts):
            params = {"JobId": job_id}
            if next_token:
                params["NextToken"] = next_token

            response = self.client.get_document_text_detection(**params)
            status = response["JobStatus"]

            if status in ("SUCCEEDED", "PARTIAL_SUCCESS"):
                return self._collect_succeeded_blocks(job_id, response)

            if status == "FAILED":
                message = response.get("StatusMessage", "sem detalhes")
                raise ValueError(f"OCR do PDF falhou no Textract: {message}")

            time.sleep(self.poll_interval_seconds)

        raise TimeoutError("OCR do PDF não concluiu dentro do tempo configurado")

    def _collect_succeeded_blocks(self, job_id: str, first_response: dict) -> list[dict]:
        blocks = list(first_response.get("Blocks", []))
        next_token = first_response.get("NextToken")

        while next_token:
            response = self.client.get_document_text_detection(
                JobId=job_id,
                NextToken=next_token,
            )
            blocks.extend(response.get("Blocks", []))
            next_token = response.get("NextToken")

        return blocks
