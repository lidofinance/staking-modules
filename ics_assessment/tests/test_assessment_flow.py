from importlib import util
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT_DIR = HERE.parent.parent

from ics_assessment.result_models import AssessmentResult, CategoryResult, CheckResult

MAIN_MODULE_PATH = ROOT_DIR / "main.py"
BATCH_MODULE_PATH = ROOT_DIR / "batch_process_forms.py"


def _load_module(path: Path, name: str):
    spec = util.spec_from_file_location(name, str(path))
    mod = util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod


def _category(name: str, score: int) -> CategoryResult:
    return CategoryResult(
        name=name,
        min_score=1,
        max_score=10,
        checks=[CheckResult("check", score, score > 0)],
        raw_score=score,
        final_score=score,
    )


def test_evaluate_assessment_aggregates_categories(monkeypatch):
    mod = _load_module(MAIN_MODULE_PATH, "ics_main")
    monkeypatch.setattr(mod.ExperienceEvaluator, "evaluate", lambda self, addrs: _category("Experience", 6))
    monkeypatch.setattr(
        mod.HumanityEvaluator,
        "evaluate",
        lambda self, addrs: _category("Humanity", 4),
    )
    monkeypatch.setattr(
        mod.EngagementEvaluator,
        "evaluate",
        lambda self, addrs: _category("Engagement", 5),
    )

    result = mod.evaluate_assessment(
        {"0xdef", "0xabc"},
        runtime_inputs=mod.AssessmentRuntimeInputs(
            humanity=mod.HumanityRuntimeInputs(discord=True),
        ),
    )
    assert result.total_score == 15
    assert result.eligible is True
    assert result.addresses == ["0xabc", "0xdef"]


def test_batch_assess_addresses_writes_report(monkeypatch, tmp_path):
    mod = _load_module(BATCH_MODULE_PATH, "ics_batch")
    log_path = tmp_path / "assessment.log"
    result = AssessmentResult(
        addresses=["0xabc"],
        categories=[_category("Experience", 6), _category("Humanity", 4), _category("Engagement", 5)],
        total_score=15,
        eligible=True,
    )

    monkeypatch.setattr(
        mod,
        "evaluate_assessment",
        lambda addresses, runtime_inputs=None: result,
    )
    monkeypatch.setattr(mod, "render_assessment_result", lambda r: "report body")

    exp, hum, eng, total, eligible = mod.assess_addresses(
        ["0xabc"],
        log_path,
        has_discord=True,
        has_twitter=False,
    )

    assert (exp, hum, eng, total, eligible) == (6, 4, 5, 15, "YES")
    assert log_path.read_text() == "report body\n"


def test_resolve_runtime_inputs_prefers_env_fetch(monkeypatch):
    mod = _load_module(MAIN_MODULE_PATH, "ics_main_runtime_env")
    monkeypatch.setenv("HUMAN_PASSPORT_API_KEY", "hp")
    monkeypatch.setenv("HIGH_SIGNAL_API_KEY", "hs")
    monkeypatch.setattr(mod, "fetch_human_passport_max", lambda addresses, api_key: (7.2, "0xhp"))
    monkeypatch.setattr(mod, "fetch_high_signal_max", lambda addresses, api_key: (85.0, "0xhs"))

    resolved = mod.resolve_runtime_inputs({"0xabc"}, allow_prompt=False)

    assert resolved.humanity.human_passport_score == 7.2
    assert resolved.humanity.human_passport_address == "0xhp"
    assert resolved.engagement.high_signal_score == 85.0
    assert resolved.engagement.high_signal_address == "0xhs"
    assert resolved.humanity.discord is None
    assert resolved.humanity.x is None


def test_resolve_runtime_inputs_prompts_when_env_missing(monkeypatch):
    mod = _load_module(MAIN_MODULE_PATH, "ics_main_runtime_prompt")
    monkeypatch.delenv("HUMAN_PASSPORT_API_KEY", raising=False)
    monkeypatch.delenv("HIGH_SIGNAL_API_KEY", raising=False)
    monkeypatch.setattr(mod.sys.stdin, "isatty", lambda: True)
    answers = iter(["5", "yes", "no", "80"])
    monkeypatch.setattr("builtins.input", lambda _: next(answers))

    resolved = mod.resolve_runtime_inputs({"0xabc"}, allow_prompt=True)

    assert resolved.humanity.human_passport_score == 5.0
    assert resolved.humanity.discord is True
    assert resolved.humanity.x is False
    assert resolved.engagement.high_signal_score == 80.0
