import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
VARIABLES = (
    "GNOSIS_RPC_URL",
    "IPFS_GATEWAY_URL",
    "MAINNET_RPC_URL",
    "HOODI_RPC_URL",
    "MAINNET_ARCHIVE_RPC_URL",
    "HOODI_ARCHIVE_RPC_URL",
)


@pytest.mark.parametrize("optional", [None, ""])
def test_missing_and_empty_optional_endpoints_use_defaults(optional):
    env = {key: value for key, value in os.environ.items() if key not in VARIABLES}
    env.update(
        PYTHON_DOTENV_DISABLED="1",
        MAINNET_RPC_URL="https://mainnet.example",
        HOODI_RPC_URL="https://hoodi.example",
    )
    if optional is not None:
        env.update(
            {
                key: optional
                for key in (
                    "GNOSIS_RPC_URL",
                    "IPFS_GATEWAY_URL",
                    "MAINNET_ARCHIVE_RPC_URL",
                    "HOODI_ARCHIVE_RPC_URL",
                )
            }
        )
    script = (
        "import json; from ics_assessment import config; "
        f"print(json.dumps([getattr(config, key) for key in {VARIABLES!r}]))"
    )
    values = json.loads(
        subprocess.check_output(
            [sys.executable, "-c", script], cwd=ROOT, env=env, text=True
        )
    )
    assert values == [
        "https://rpc.gnosis.gateway.fm",
        "https://gateway.pinata.cloud/ipfs",
        "https://mainnet.example",
        "https://hoodi.example",
        "https://mainnet.example",
        "https://hoodi.example",
    ]


def test_ipfs_override_is_used_by_both_report_downloaders(monkeypatch):
    from ics_assessment import sync
    from ics_assessment.experience import sync_hoodi

    urls = []

    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"report": "fixture"}

    def get(url, **kwargs):
        urls.append(url)
        return Response()

    monkeypatch.setattr(
        sync.experience_jobs, "IPFS_GATEWAY_URL", "https://gateway.example/ipfs"
    )
    monkeypatch.setattr(sync_hoodi, "IPFS_GATEWAY_URL", "https://gateway.example/ipfs")
    monkeypatch.setattr(sync.experience_jobs.requests, "get", get)
    assert sync.experience_jobs.request_performance_report("CID") == {
        "report": "fixture"
    }
    assert sync_hoodi.request_performance_report("CID") == {"report": "fixture"}
    assert urls == ["https://gateway.example/ipfs/CID"] * 2


def test_ipfs_configuration_trims_trailing_slashes():
    env = dict(
        os.environ,
        PYTHON_DOTENV_DISABLED="1",
        IPFS_GATEWAY_URL="https://gateway.example/ipfs///",
    )
    result = subprocess.check_output(
        [
            sys.executable,
            "-c",
            "from ics_assessment.config import IPFS_GATEWAY_URL; print(IPFS_GATEWAY_URL)",
        ],
        cwd=ROOT,
        env=env,
        text=True,
    )
    assert result.strip() == "https://gateway.example/ipfs"
