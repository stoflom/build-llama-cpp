#!/usr/bin/env python3
"""
OCR utility: Convert PDF, TIFF, PNG, JPG, etc. (refer  PyMuPDF) to Markdown through
AI API, e.g. LightOn AI model running locally on llama.cpp server.

Usage:
  ./ocr-ai.py input.pdf output.md  [--first N] [--last N]  ... see ./ocr-ai.py --help
"""

import argparse
import base64
import logging
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Optional, Set

import pymupdf
import requests

# Configuration Constants
MAX_EDGE = 1540
DEFAULT_MAX_TOKENS = 4096
DEFAULT_RETRIES = 3
DEFAULT_BACKOFF = 2
DEFAULT_HOST = 'http://localhost:8080/v1/chat/completions'
DEFAULT_WORKERS = 4
SUPPORTED_EXTENSIONS: Set[str] = {'.pdf', '.tiff', '.tif', '.png', '.jpg', '.jpeg'}

# Setup Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)

class OCRClient:
    """Handles all communication with the LightOnOCR API."""

    def __init__(self, url: str, retries: int, backoch: int, timeout: int):
        self.url = url
        self.retries = retries
        self.backoff = backoch
        self.timeout = timeout
        self.session = requests.Session()

    def transcribe_image(self, base64_image: str) -> str:
        payload = {
            "model": "LightOnOCR-2-1B",
            "messages": [
                {
                    "role": "system",
                    "content": "You are a professional OCR assistant. Transcribe the provided image into accurate Markdown text. Process the full image."
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{base64_image}"}}
                    ]
                }
            ],
            "max_tokens": DEFAULT_MAX_TOKENS,
            "temperature": 0.1,
            "top_p": 0.9
        }

        last_exc = None
        current_backoff = self.backoff

        for attempt in range(1, self.retries + 1):
            try:
                response = self.session.post(self.url, json=payload, timeout=self.timeout)
                response.raise_for_status()

                result = response.json()
                choices = result.get('choices')
                if not choices:
                    raise ValueError("API returned no choices.")

                content = choices[0].get('message', {}).get('content')
                if content is None:
                    raise ValueError("API response missing content.")

                return content

            except Exception as e:
                last_exc = e
                if attempt < self.retries:
                    logger.warning(f"Attempt {attempt} failed: {e}. Retrying in {current_backoff}s...")
                    time.sleep(current_backoff)
                    current_backoff *= 2
                else:
                    raise last_exc

class DocumentProcessor:
    """Handles loading and rasterizing PDF, TIFF, etc.  files."""

    def __init__(self, input_path: str, dpi: int):
        self.input_path = Path(input_path)
        self.dpi = dpi

        if not self.input_path.exists():
            raise FileNotFoundError(f"File not found: {input_path}")

        if self.input_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            raise ValueError(f"Unsupported file extension: {self.input_path.suffix}. "
                             f"Supported: {SUPPORTED_EXTENSIONS}")

        # PyMuPDF handles PDF, TIFF, PNG, JPG via the same interface
        self.doc = pymupdf.open(str(self.input_path))

    def get_page_count(self) -> int:
        return len(self.doc)

    def render_page_as_base64(self, page_index: int) -> str:
        """Renders a specific page/frame to a base64 encoded PNG string."""
        page = self.doc[page_index]

        # Standardize scaling logic.
        # 72 points per inch is the PDF standard.
        # We scale based on target DPI to ensure consistent OCR quality.
        scale = self.dpi / 72

        # Check if the resulting dimensions exceed the MAX_EDGE limit (Model optimization)
        current_max_edge = max(page.rect.width, page.rect.height) * scale
        if current_max_edge > MAX_EDGE:
            scale = MAX_EDGE / max(page.rect.width, page.rect.height)
            logger.debug(f"Page {page_index + 1} scaled down to fit {MAX_EDGE}px limit.")

        matrix = pymupdf.Matrix(scale, scale)
        pix = page.get_pixmap(matrix=matrix)
        img_bytes = pix.tobytes("png")
        return base64.b64encode(img_bytes).decode()

    def close(self):
        self.doc.close()

def parse_pages(pages_str: str, total_pages: int) -> List[int]:
    """Parse comma-separated page list with optional ranges (e.g., '1,3,5-10')."""
    page_indices = set()
    parts = pages_str.split(',')

    for part in parts:
        part = part.strip()
        if not part:
            continue
        if '-' in part:
            # Range like 5-10
            range_parts = part.split('-')
            if len(range_parts) != 2:
                raise ValueError(f"Invalid range format: {part}")
            start, end = int(range_parts[0]), int(range_parts[1])
            if start > end:
                raise ValueError(f"Invalid range: {part} (start > end)")
            page_indices.update(range(start - 1, end))  # Convert to 0-indexed
        else:
            # Single page
            page_num = int(part)
            page_indices.add(page_num - 1)  # Convert to 0-indexed

    # Validate all pages are within bounds
    invalid_pages = [p + 1 for p in page_indices if p < 0 or p >= total_pages]
    if invalid_pages:
        raise ValueError(f"Page(s) out of range (1-{total_pages}): {invalid_pages}")

    return list(page_indices)


def worker(page_idx: int, doc_proc: DocumentProcessor, ocr_client: OCRClient, use_marker: bool) -> tuple[int, str]:
    """The task performed by each thread."""
    try:
        img_b64 = doc_proc.render_page_as_base64(page_idx)
        text = ocr_client.transcribe_image(img_b64)

        marker = f"[[ PAGE {page_idx + 1} ]]\n\n" if use_marker else ""
        return page_idx, marker + text
    except Exception as e:
        logger.error(f"Error on page {page_idx + 1}: {e}")
        raise

def main():
    parser = argparse.ArgumentParser(description='OCR multi-format documents (PDF, TIFF, PNG, JPG) to Markdown')
    parser.add_argument('input', help='Path to input file')
    parser.add_argument('output', help='Path to output markdown file')
    parser.add_argument('-P', '--pages', type=str, help='Comma-separated list of pages to process (e.g., 1,3,5-10). If not specified, all pages will be processed.')
    parser.add_argument('-p', '--page-marker', action='store_true', help='Add page markers')
    parser.add_argument('-u', '--url', default=DEFAULT_HOST, help='OCR service URL')
    parser.add_argument('-d', '--dpi', type=int, default=200, help='Target DPI (default: 200)')
    parser.add_argument('-t', '--timeout', type=int, default=300, help='Timeout (seconds)')
    parser.add_argument('-r', '--retries', type=int, default=DEFAULT_RETRIES, help='Retries')
    parser.add_argument('-b', '--backoff', type=int, default=DEFAULT_BACKOFF, help='Initial backoff (seconds)')
    parser.add_argument('-w', '--workers', type=int, default=DEFAULT_WORKERS, help='Concurrent threads')
    args = parser.parse_args()

    doc_proc = None
    try:
        doc_proc = DocumentProcessor(args.input, args.dpi)
        total_pages = doc_proc.get_page_count()

        # Parse pages argument
        if args.pages:
            page_indices = parse_pages(args.pages, total_pages)
            if not page_indices:
                logger.error("Invalid pages specification.")
                return
            pages_to_process = list(sorted(page_indices))
            start_idx = min(pages_to_process)
            end_idx = max(pages_to_process) + 1
            logger.info(f"Processing specific pages: {args.pages}")
        else:
            # Process all pages
            pages_to_process = list(range(total_pages))
            start_idx = 0
            end_idx = total_pages
            logger.info(f"Processing all {total_pages} pages")

        ocr_client = OCRClient(args.url, args.retries, args.backoff, args.timeout)

        results: Dict[int, str] = {}
        failed_pages: List[int] = []

        logger.info(f"Processing: {args.input} ({total_pages} pages total, range {start_idx+1}-{end_idx})")

        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = {
                executor.submit(worker, i, doc_proc, ocr_client, args.page_marker): i
                for i in pages_to_process
            }

            for future in as_completed(futures):
                page_num = futures[future]
                try:
                    idx, content = future.result()
                    results[idx] = content
                    logger.info(f"Page {idx + 1} done.")
                except Exception:
                    failed_pages.append(page_num + 1)

        # Sequential write to maintain document order
        with open(args.output, 'w', encoding='utf-8') as out_file:
            for i in pages_to_process:
                if i in results:
                    out_file.write(results[i] + "\n")

        logger.info(f"Finished. Output: {args.output}")
        if failed_pages:
            logger.error(f"Failed pages: {failed_pages}")

    except Exception as e:
        logger.error(f"Critical error: {e}")
        sys.exit(1)
    finally:
        if doc_proc:
            doc_proc.close()

if __name__ == "__main__":
    main()
