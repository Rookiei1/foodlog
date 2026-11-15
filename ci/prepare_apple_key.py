"""Write the App Store Connect API key into the runner temp directory. Never print secret values."""
from __future__ import annotations

import base64
import binascii
import os
import textwrap
from pathlib import Path


def normalize_private_key(raw: str) -> str:
    text = raw.strip().replace("\\r\\n", "\n").replace("\\n", "\n")
    if "-----BEGIN PRIVATE KEY-----" in text or "-----BEGIN EC PRIVATE KEY-----" in text:
        return text + "\n"

    compact = "".join(text.split())
    try:
        decoded_bytes = base64.b64decode(compact, validate=False)
    except binascii.Error as exc:
        raise RuntimeError(
            f"ASC_PRIVATE_KEY (length={len(raw.strip())}) is neither a PEM private key nor valid base64."
        ) from exc

    # Case 1: base64-encoded full PEM text
    try:
        decoded_str = decoded_bytes.decode("utf-8").strip().replace("\\n", "\n")
        if "-----BEGIN PRIVATE KEY-----" in decoded_str or "-----BEGIN EC PRIVATE KEY-----" in decoded_str:
            return decoded_str + "\n"
    except UnicodeDecodeError:
        pass

    # Case 2: bare base64 body of a PKCS#8 .p8 file (ASN.1 SEQUENCE starts with 0x30)
    if decoded_bytes and decoded_bytes[0] == 0x30 and len(decoded_bytes) >= 64:
        b64_lines = "\n".join(textwrap.wrap(base64.b64encode(decoded_bytes).decode("ascii"), 64))
        return f"-----BEGIN PRIVATE KEY-----\n{b64_lines}\n-----END PRIVATE KEY-----\n"

    raise RuntimeError(
        f"ASC_PRIVATE_KEY (length={len(raw.strip())}) does not contain a valid .p8 PEM or PKCS#8 key."
    )


def normalize_ssh_key(raw: str) -> str:
    text = raw.strip().replace("\\r\\n", "\n").replace("\\n", "\n")
    if "-----BEGIN " in text:
        return text + "\n"
    compact = "".join(text.split())
    try:
        decoded_str = base64.b64decode(compact, validate=False).decode("utf-8").strip().replace("\\n", "\n")
        if "-----BEGIN " in decoded_str:
            return decoded_str + "\n"
    except (binascii.Error, UnicodeDecodeError):
        pass
    return text + "\n"


def main() -> None:
    required = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY")
    missing = [name for name in required if not os.environ.get(name, "").strip()]
    if missing:
        raise RuntimeError("Configure these GitHub Actions secrets: " + ", ".join(missing))

    value = normalize_private_key(os.environ["ASC_PRIVATE_KEY"])

    path = Path(os.environ["RUNNER_TEMP"]) / "foodlog-asc" / "AuthKey.p8"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8", newline="\n")
    path.chmod(0o600)

    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as environment:
        environment.write(f"ASC_KEY_PATH={path}\n")

    raw_deploy_key = os.environ.get("SIGNING_DEPLOY_KEY", "").strip()
    if raw_deploy_key:
        ssh_dir = Path.home() / ".ssh"
        ssh_dir.mkdir(parents=True, exist_ok=True)
        ssh_dir.chmod(0o700)
        ssh_key_path = ssh_dir / "foodlog_signing"
        ssh_key_path.write_text(normalize_ssh_key(raw_deploy_key), encoding="utf-8", newline="\n")
        ssh_key_path.chmod(0o600)

    print("Prepared the Apple API key in the temporary runner directory.")


if __name__ == "__main__":
    main()
