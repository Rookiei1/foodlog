"""Write the App Store Connect API key and SSH deploy key into temporary runner paths safely. Never print secret values."""
from __future__ import annotations

import base64
import binascii
import os
import re
import subprocess
import textwrap
from pathlib import Path

PEM_PATTERN = re.compile(r"-----BEGIN ([A-Z0-9 ]+)-----(.*?)-----END \1-----", re.DOTALL)


def rewrap_pem(key_type: str, body: str, width: int) -> str:
    compact = "".join(body.split())
    wrapped = "\n".join(textwrap.wrap(compact, width))
    return f"-----BEGIN {key_type}-----\n{wrapped}\n-----END {key_type}-----\n"


def normalize_private_key(raw: str) -> str:
    text = raw.strip().replace("\\r\\n", "\n").replace("\\n", "\n")
    match = PEM_PATTERN.search(text)
    if match:
        return rewrap_pem(match.group(1), match.group(2), 64)

    compact = "".join(text.split())
    try:
        decoded_bytes = base64.b64decode(compact, validate=False)
    except binascii.Error as exc:
        raise RuntimeError(
            f"ASC_PRIVATE_KEY (length={len(raw.strip())}) is neither a PEM private key nor valid base64."
        ) from exc

    try:
        decoded_str = decoded_bytes.decode("utf-8").strip().replace("\\n", "\n")
        nested = PEM_PATTERN.search(decoded_str)
        if nested:
            return rewrap_pem(nested.group(1), nested.group(2), 64)
    except UnicodeDecodeError:
        pass

    if decoded_bytes and decoded_bytes[0] == 0x30 and len(decoded_bytes) >= 64:
        b64_str = base64.b64encode(decoded_bytes).decode("ascii")
        return rewrap_pem("PRIVATE KEY", b64_str, 64)

    raise RuntimeError(
        f"ASC_PRIVATE_KEY (length={len(raw.strip())}) does not contain a valid .p8 PEM or PKCS#8 key."
    )


def normalize_ssh_key(raw: str) -> str:
    text = raw.strip().replace("\\r\\n", "\n").replace("\\n", "\n")
    match = PEM_PATTERN.search(text)
    if match:
        key_type = match.group(1)
        width = 70 if "OPENSSH" in key_type else 64
        return rewrap_pem(key_type, match.group(2), width)

    compact = "".join(text.split())
    try:
        decoded_bytes = base64.b64decode(compact, validate=False)
    except binascii.Error as exc:
        raise RuntimeError(
            f"SIGNING_DEPLOY_KEY (length={len(raw.strip())}) is neither PEM nor valid base64."
        ) from exc

    try:
        decoded_str = decoded_bytes.decode("utf-8").strip().replace("\\n", "\n")
        nested = PEM_PATTERN.search(decoded_str)
        if nested:
            key_type = nested.group(1)
            width = 70 if "OPENSSH" in key_type else 64
            return rewrap_pem(key_type, nested.group(2), width)
    except UnicodeDecodeError:
        pass

    if decoded_bytes.startswith(b"openssh-key-v1\x00"):
        b64_str = base64.b64encode(decoded_bytes).decode("ascii")
        return rewrap_pem("OPENSSH PRIVATE KEY", b64_str, 70)

    if decoded_bytes and decoded_bytes[0] == 0x30 and len(decoded_bytes) >= 64:
        b64_str = base64.b64encode(decoded_bytes).decode("ascii")
        return rewrap_pem("PRIVATE KEY", b64_str, 64)

    raise RuntimeError(
        f"SIGNING_DEPLOY_KEY (length={len(raw.strip())}) is not a valid OpenSSH or PEM private key."
    )


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
        check = subprocess.run(
            ["ssh-keygen", "-y", "-f", str(ssh_key_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=False,
        )
        if check.returncode != 0:
            err = check.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"Normalized SIGNING_DEPLOY_KEY failed ssh-keygen validation: {err}")

    print("Prepared the Apple API key and verified SSH deploy key format.")


if __name__ == "__main__":
    main()
