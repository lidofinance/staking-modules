import json
from unittest.mock import Mock

import pytest
import requests

from ics_assessment.humanity import sources


def response(status, payload):
    result = requests.Response()
    result.status_code = status
    result._content = json.dumps(payload).encode()
    return result


@pytest.fixture
def get(monkeypatch):
    mock = Mock()
    monkeypatch.setattr(sources.requests, "get", mock)
    monkeypatch.setattr(sources.time, "sleep", lambda seconds: None)
    return mock


def test_passport_fetches_cutoff_and_preserves_max_floor(get, monkeypatch):
    monkeypatch.setattr(sources, "HUMAN_PASSPORT_CUTOFF_DATE", "2026-09-14T23:59:59Z")
    scores = {"0xaaa": "7.9", "0xbbb": "12.3"}
    get.side_effect = lambda url, **kwargs: response(200, {"score": scores[url.split("/")[-2]]})

    assert sources.fetch_human_passport_max(set(scores), "test-key") == (12, "0xbbb")
    assert get.call_count == 2
    for call in get.call_args_list:
        assert call.args[0] in {
            f"https://api.passport.xyz/v2/stamps/11737/score/{address}/history"
            for address in scores
        }
        assert call.kwargs == {
            "headers": {"X-API-Key": "test-key"},
            "params": {"created_at": "2026-09-14T23:59:59Z"},
            "timeout": 60,
        }


def test_passport_missing_history_does_not_discard_other_address(get):
    get.side_effect = lambda url, **kwargs: (
        response(404, {"detail": "No Score Found"})
        if "/0xaaa/" in url else response(200, {"score": "8.7"})
    )
    assert sources.fetch_human_passport_max({"0xaaa", "0xbbb"}, "test-key") == (8, "0xbbb")


def test_passport_no_history_has_no_score_or_source_address(get):
    get.return_value = response(404, {"detail": "No Score Found"})
    assert sources.fetch_human_passport_max({"0xaaa"}, "test-key") == (0, None)
    assert get.call_count == 1


def test_passport_without_key_does_not_request(get):
    assert sources.fetch_human_passport_max({"0xaaa"}, None) == (None, None)
    get.assert_not_called()


@pytest.mark.parametrize("status", [401, 403, 429, 500])
def test_passport_api_errors_propagate_without_latest_fallback(get, status):
    get.return_value = response(status, {"detail": "API error"})
    with pytest.raises(requests.HTTPError):
        sources.fetch_human_passport_max({"0xaaa"}, "test-key")
    assert get.call_count == 1


def test_passport_timeout_propagates(get):
    get.side_effect = requests.Timeout()
    with pytest.raises(requests.Timeout):
        sources.fetch_human_passport_max({"0xaaa"}, "test-key")
