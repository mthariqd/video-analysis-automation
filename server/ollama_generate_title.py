"""
Ollama Title Generator
Reads input.txt and system_prompt_title.txt and generates a video title to generated_title.txt
"""
import sys
import requests
import re
from pathlib import Path

from ollama_config import MODEL_NAME, OLLAMA_GENERATE_URL as OLLAMA_URL, TIMEOUT_S, auth_headers

# Fix Windows console encoding for emoji support
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')

SCRIPTS_DIR = Path(__file__).parent.resolve()
SYSTEM_PROMPT_FILE = SCRIPTS_DIR / "system_prompt_title.txt"
INPUT_FILE = "input.txt"
OUTPUT_FILE = "generated_title.txt"

def to_plain_text(text: str) -> str:
    """Strip emoji and other non-plain characters, keeping ASCII letters, digits and punctuation."""
    replacements = {
        "‘": "'", "’": "'", "“": '"', "”": '"',
        "–": "-", "—": "-", "…": "...",
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)
    text = re.sub(r"[^\x20-\x7E]", "", text)
    return " ".join(text.split())

def main():
    try:
        if not SYSTEM_PROMPT_FILE.exists():
            raise FileNotFoundError(f"Missing system prompt: {SYSTEM_PROMPT_FILE}")
        system_prompt = SYSTEM_PROMPT_FILE.read_text(encoding="utf-8")
        
        input_path = Path(INPUT_FILE)
        if not input_path.exists():
            raise FileNotFoundError(f"Missing script file: {INPUT_FILE}")
        script_text = input_path.read_text(encoding="utf-8", errors="ignore")
        
        user_message = f"SCRIPT:\n{script_text}\n"
        
        payload = {
            "model": MODEL_NAME,
            "prompt": user_message,
            "system": system_prompt,
            "stream": False
        }
        
        print("[AI] Generating title via Ollama...")
        resp = requests.post(OLLAMA_URL, json=payload, headers=auth_headers(), timeout=TIMEOUT_S)
        resp.raise_for_status()
        
        title = resp.json().get("response", "").strip()
        title = re.sub(r'<think>.*?</think>', '', title, flags=re.DOTALL | re.IGNORECASE).strip()
        
        title = to_plain_text(title)
        
        Path(OUTPUT_FILE).write_text(title, encoding="utf-8")
        print(f"[OK] Title generated: {title}")
        
    except Exception as e:
        print(f"[ERROR] Title generation failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
