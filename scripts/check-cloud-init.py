#!/usr/bin/env python3
"""check-cloud-init.py - render the OCI cloud-init template and validate it.

Renders infra/oci/cloud-init.yaml.tftpl the way Terraform's templatefile()
does (the same variable map as infra/oci/main.tf), then checks:

  * the result parses as YAML (catches $${} / interpolation mistakes)
  * every write_files body decodes (text, b64, gz+b64)
  * every decoded *.sh passes `bash -n`
  * the rendered user_data still fits OCI's 32,000-byte metadata cap

Run locally or from CI before `terraform apply`.
"""
import base64
import gzip
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "infra/oci/cloud-init.yaml.tftpl"
MAX_USER_DATA = 32000


def gz(path: Path) -> str:
    return base64.b64encode(gzip.compress(path.read_bytes(), 9)).decode()


def b64(text: str) -> str:
    return base64.b64encode(text.encode()).decode()


def build_vars() -> dict:
    """Mirror the templatefile() arguments in infra/oci/main.tf."""
    return {
        "ttyd_password": "p@ss:word$with/specials",
        "tunnel_token_b64": b64("x" * 184),
        "hermes_env_b64": b64(
            "DEEPSEEK_API_KEY=" + "x" * 35 + "\n"
            "TELEGRAM_BOT_TOKEN=" + "x" * 46 + "\n"
            "TELEGRAM_ALLOWED_USERS=123456789\n"
        ),
        "dsh_env_b64": b64("DEEPSEEK_API_KEY=" + "x" * 35 + "\n"),
        "hermes_config_gzb64": gz(ROOT / "infra/hermes/config.yaml"),
        "hermes_compose_gzb64": gz(ROOT / "infra/hermes/docker-compose.yml"),
        "provision_gzb64": gz(ROOT / "scripts/provision.sh"),
        "maintenance_gzb64": gz(ROOT / "scripts/maintenance.sh"),
    }


def render() -> str:
    template = TEMPLATE.read_text()
    values = build_vars()
    # Terraform: $${ is a literal ${, ${name} is an interpolation.
    template = template.replace("$${", "\x01{")

    def replace(match: re.Match) -> str:
        name = match.group(1)
        if name not in values:
            sys.exit(f"check-cloud-init: unknown template variable: {name}")
        return values[name]

    rendered = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", replace, template)
    return rendered.replace("\x01{", "${")


def main() -> int:
    rendered = render()
    doc = yaml.safe_load(rendered)
    files = {entry["path"]: entry for entry in doc["write_files"]}

    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        for path, entry in sorted(files.items()):
            encoding = entry.get("encoding", "text")
            content = str(entry["content"])
            if encoding == "gz+b64":
                decoded = gzip.decompress(base64.b64decode(content)).decode()
            elif encoding == "b64":
                decoded = base64.b64decode(content).decode()
            else:
                decoded = content
            if path.endswith(".sh"):
                target = Path(tmp) / Path(path).name
                target.write_text(decoded)
                result = subprocess.run(
                    ["bash", "-n", str(target)], capture_output=True, text=True
                )
                if result.returncode != 0:
                    failures.append(f"{path}: bash -n failed: {result.stderr.strip()}")
            elif path.endswith("docker-compose.yml"):
                try:
                    yaml.safe_load(decoded)
                except yaml.YAMLError as exc:
                    failures.append(f"{path}: invalid compose YAML: {exc}")

    user_data = len(base64.b64encode(rendered.encode()))
    print(f"cloud-init: {len(files)} write_files, user_data {user_data}/{MAX_USER_DATA} bytes")
    if user_data > MAX_USER_DATA:
        failures.append(f"user_data exceeds the OCI metadata cap ({user_data} > {MAX_USER_DATA})")
    if doc.get("runcmd") != [["bash", "/usr/local/sbin/provision.sh"]]:
        failures.append(f"unexpected runcmd: {doc.get('runcmd')}")

    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())