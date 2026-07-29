import pytest

from ics_assessment.experience import sync_hoodi as mod


def make_reports(day_epochs, statuses_per_frame, version="v1"):
    """
    statuses_per_frame: List[dict] mapping op_id -> status (True/False/None)
    Returns list[(ReportMeta, rep)] where rep carries 'status' for mocks.
    """
    reports = []
    epoch0 = 10_000
    for i, status_map in enumerate(statuses_per_frame):
        start = epoch0 + i * day_epochs
        end = start + day_epochs
        cid = f"CID{i+1}"
        meta = mod.ReportMeta(cid, version=version, start_epoch=start, end_epoch=end)
        rep = {"status": status_map}
        reports.append((meta, rep))
    return reports


def patch_status_monkey(monkeypatch):
    def _v1(rep, op_id):
        return (rep.get("status") or {}).get(op_id, None)

    def _v2(rep, op_id):
        return (rep.get("status") or {}).get(op_id, None)

    def _v3(rep, op_id):
        return (rep.get("status") or {}).get(op_id, None)

    monkeypatch.setattr(mod, "operator_passes_in_report_v1", _v1)
    monkeypatch.setattr(mod, "operator_passes_in_report_v2", _v2)
    monkeypatch.setattr(mod, "operator_passes_in_report_v3", _v3)


def test_append_report_frames_raises_with_cid_for_missing_frame():
    with pytest.raises(
        ValueError,
        match="invalid Hoodi performance report frame: CID",
    ):
        mod.append_report_frames([], "CID", {"_ver": 1, "frames": [{}]})


def test_iter_performance_report_frames_supports_v3_wrapper():
    frame = {
        "frame": [91325, 92899],
        "operators": {
            "1": {
                "validators": {
                    "v1": {
                        "distributed_rewards": 1,
                    }
                }
            }
        },
    }

    assert mod.iter_performance_report_frames({"_ver": 1, "frames": [frame]}) == [
        ("v3", frame),
    ]


def test_v3_good_logic_used(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    statuses = [{"8": True} for _ in range(3)]
    reports = make_reports(day_epochs, statuses, version="v3")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "8" in eligible


def test_v3_dispatch_uses_v3_parser(monkeypatch):
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    reports = make_reports(day_epochs, [{"8": True}], version="v3")

    monkeypatch.setattr(mod, "operator_passes_in_report_v1", lambda rep, op_id: None)
    monkeypatch.setattr(mod, "operator_passes_in_report_v2", lambda rep, op_id: False)
    monkeypatch.setattr(mod, "operator_passes_in_report_v3", lambda rep, op_id: True)

    eligible = mod.evaluate_eligibility_window(reports, min_days=1)

    assert "8" in eligible


def test_all_good_contiguous_meets_threshold(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    # 3 days threshold, 3 good frames
    statuses = [{"1": True}, {"1": True}, {"1": True}]
    reports = make_reports(day_epochs, statuses, version="v1")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "1" in eligible


def test_good_with_empties_meets_threshold(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    # GOOD, EMPTY, GOOD, EMPTY, GOOD => 3 days good
    statuses = [{"1": True}, {"1": None}, {"1": True}, {"1": None}, {"1": True}]
    reports = make_reports(day_epochs, statuses, version="v1")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "1" in eligible


def test_bad_does_not_reset_and_meets(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    # With new cumulative policy: GOOD, GOOD, BAD, GOOD => 3 GOOD days total
    statuses = [
        {"1": True},
        {"1": True},
        {"1": False},
        {"1": True},
    ]
    reports = make_reports(day_epochs, statuses, version="v1")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "1" in eligible


def test_only_empty_never_meets(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    statuses = [{"1": None} for _ in range(5)]
    reports = make_reports(day_epochs, statuses, version="v1")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "1" not in eligible


def test_operator_absent_entirely(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    # status maps do not include op '2' at all
    statuses = [{"1": True}, {"1": True}, {"1": True}]
    reports = make_reports(day_epochs, statuses, version="v1")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "2" not in eligible


def test_v2_good_logic_used(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    # v2 frames, all good for op '3'
    statuses = [{"3": True} for _ in range(3)]
    reports = make_reports(day_epochs, statuses, version="v2")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "3" in eligible


def test_mixed_versions_accumulate(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    # v1 good, v2 good, v1 empty, v2 good -> meets 3 days
    reports = []
    reports += make_reports(day_epochs, [{"4": True}], version="v1")
    reports += make_reports(day_epochs, [{"4": True}], version="v2")
    reports += make_reports(day_epochs, [{"4": None}], version="v1")
    reports += make_reports(day_epochs, [{"4": True}], version="v2")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "4" in eligible


def test_multiple_ops_one_meets_other_not(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    statuses = [
        {"5": True, "6": True},
        {"5": True, "6": None},
        {"5": True, "6": False},  # '6' reset and fails to reach 3 days
    ]
    reports = make_reports(day_epochs, statuses, version="v1")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "5" in eligible
    assert "6" not in eligible


def test_exact_boundary_3_days(monkeypatch):
    patch_status_monkey(monkeypatch)
    day_epochs = mod.SECONDS_PER_DAY // mod.EPOCH_SECONDS
    # Exactly 3 days threshold with 3 good frames
    statuses = [{"7": True}, {"7": True}, {"7": True}]
    reports = make_reports(day_epochs, statuses, version="v1")
    eligible = mod.evaluate_eligibility_window(reports, min_days=3)
    assert "7" in eligible
