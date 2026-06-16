import re
import zlib
from collections import defaultdict


OBJECT_PATTERN = re.compile(rb"(\d+)\s+0\s+obj\s*(.*?)\s*endobj", re.DOTALL)
STREAM_PATTERN = re.compile(rb"stream\r?\n(.*?)\r?\nendstream", re.DOTALL)
FONT_REF_PATTERN = re.compile(rb"/(F\d+)\s+(\d+)\s+0\s+R")
TO_UNICODE_PATTERN = re.compile(rb"/ToUnicode\s+(\d+)\s+0\s+R")
TEXT_BLOCK_PATTERN = re.compile(rb"BT(.*?)ET", re.DOTALL)
FONT_PATTERN = re.compile(rb"/(F\d+)\s+[\d.]+\s+Tf")
TEXT_MATRIX_PATTERN = re.compile(
    rb"[-\d.]+\s+[-\d.]+\s+[-\d.]+\s+[-\d.]+\s+([-\d.]+)\s+([-\d.]+)\s+Tm"
)
LITERAL_TEXT_PATTERN = re.compile(rb"\((.*?)\)\s*Tj", re.DOTALL)
HEX_TEXT_PATTERN = re.compile(rb"<([0-9A-Fa-f]+)>\s*Tj")


def extract_text(pdf_bytes: bytes) -> str:
    """Extrai texto de PDFs textuais simples usando ToUnicode CMaps."""
    objects = _parse_objects(pdf_bytes)
    font_maps = _extract_font_maps(objects)
    text_entries = _extract_text_entries(objects, font_maps)
    return _entries_to_text(text_entries)


def _parse_objects(pdf_bytes: bytes) -> dict[int, bytes]:
    return {
        int(match.group(1)): match.group(2)
        for match in OBJECT_PATTERN.finditer(pdf_bytes)
    }


def _stream_data(obj: bytes) -> bytes | None:
    match = STREAM_PATTERN.search(obj)
    if not match:
        return None

    stream = match.group(1)
    if b"/FlateDecode" not in obj:
        return stream

    try:
        return zlib.decompress(stream)
    except zlib.error:
        return None


def _extract_font_maps(objects: dict[int, bytes]) -> dict[str, dict[int, str]]:
    font_maps = {}

    for obj in objects.values():
        for font_name, font_obj_ref in FONT_REF_PATTERN.findall(obj):
            font_obj = objects.get(int(font_obj_ref), b"")
            to_unicode_match = TO_UNICODE_PATTERN.search(font_obj)
            if not to_unicode_match:
                continue

            cmap_obj = objects.get(int(to_unicode_match.group(1)), b"")
            cmap_stream = _stream_data(cmap_obj)
            if cmap_stream:
                font_maps[font_name.decode("ascii")] = _parse_cmap(cmap_stream)

    return font_maps


def _parse_cmap(cmap_stream: bytes) -> dict[int, str]:
    cmap = {}
    text = cmap_stream.decode("latin-1", errors="ignore")

    for block in re.findall(r"beginbfchar\s*(.*?)\s*endbfchar", text, re.DOTALL):
        for source, target in re.findall(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block):
            decoded = _decode_utf16_hex(target)
            if decoded:
                cmap[int(source, 16)] = decoded

    for block in re.findall(r"beginbfrange\s*(.*?)\s*endbfrange", text, re.DOTALL):
        for start, end, target in re.findall(
            r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>",
            block,
        ):
            start_code = int(start, 16)
            end_code = int(end, 16)
            target_code = int(target, 16)

            for code in range(start_code, end_code + 1):
                decoded = _decode_utf16_int(target_code + code - start_code)
                if decoded:
                    cmap[code] = decoded

    return cmap


def _extract_text_entries(
    objects: dict[int, bytes],
    font_maps: dict[str, dict[int, str]],
) -> list[tuple[int, float, float, str]]:
    entries = []
    page_index = 0

    for obj_number in sorted(objects):
        stream = _stream_data(objects[obj_number])
        if not stream or b"Tj" not in stream or b"Tm" not in stream:
            continue

        page_index += 1
        for block in TEXT_BLOCK_PATTERN.findall(stream):
            font_name = _block_font_name(block)
            coordinates = _block_coordinates(block)
            if not font_name or not coordinates:
                continue

            x, y = coordinates
            cmap = font_maps.get(font_name, {})

            for raw_text in _block_text_values(block):
                text = _decode_text(raw_text, cmap)
                if text.strip():
                    entries.append((page_index, round(y, 1), x, text))

    return entries


def _block_font_name(block: bytes) -> str | None:
    match = FONT_PATTERN.search(block)
    return match.group(1).decode("ascii") if match else None


def _block_coordinates(block: bytes) -> tuple[float, float] | None:
    match = TEXT_MATRIX_PATTERN.search(block)
    if not match:
        return None
    return float(match.group(1)), float(match.group(2))


def _block_text_values(block: bytes) -> list[bytes]:
    values = []

    for match in LITERAL_TEXT_PATTERN.finditer(block):
        values.append(_decode_pdf_literal(match.group(1)))

    for match in HEX_TEXT_PATTERN.finditer(block):
        values.append(bytes.fromhex(match.group(1).decode("ascii")))

    return values


def _decode_text(raw_text: bytes, cmap: dict[int, str]) -> str:
    if not cmap:
        return raw_text.decode("latin-1", errors="ignore")

    chars = []
    for index in range(0, len(raw_text) - 1, 2):
        code = (raw_text[index] << 8) + raw_text[index + 1]
        chars.append(cmap.get(code, ""))
    return "".join(chars)


def _decode_pdf_literal(value: bytes) -> bytes:
    output = bytearray()
    index = 0

    while index < len(value):
        char = value[index]

        if char == 92 and index + 1 < len(value):
            index += 1
            escaped = value[index]
            replacements = {
                ord("n"): 10,
                ord("r"): 13,
                ord("t"): 9,
                ord("b"): 8,
                ord("f"): 12,
                ord("("): 40,
                ord(")"): 41,
                ord("\\"): 92,
            }

            if escaped in replacements:
                output.append(replacements[escaped])
            elif ord("0") <= escaped <= ord("7"):
                octal = bytes([escaped])
                consumed = 0
                while (
                    index + 1 < len(value)
                    and consumed < 2
                    and ord("0") <= value[index + 1] <= ord("7")
                ):
                    index += 1
                    consumed += 1
                    octal += bytes([value[index]])
                output.append(int(octal, 8))
            else:
                output.append(escaped)
        else:
            output.append(char)

        index += 1

    return bytes(output)


def _entries_to_text(entries: list[tuple[int, float, float, str]]) -> str:
    lines = []

    for page in sorted({entry[0] for entry in entries}):
        rows = defaultdict(list)
        for entry_page, y, x, text in entries:
            if entry_page == page:
                rows[y].append((x, text))

        for y in sorted(rows.keys(), reverse=True):
            line = " ".join(text for x, text in sorted(rows[y]))
            lines.append(_normalize_spaces(line))

    return "\n".join(line for line in lines if line)


def _decode_utf16_hex(value: str) -> str | None:
    try:
        return bytes.fromhex(value).decode("utf-16-be")
    except UnicodeDecodeError:
        return None


def _decode_utf16_int(value: int) -> str | None:
    byte_length = max(2, ((value.bit_length() + 7) // 8))
    try:
        return value.to_bytes(byte_length, "big").decode("utf-16-be")
    except UnicodeDecodeError:
        return None


def _normalize_spaces(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()
