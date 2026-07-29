from ics_assessment.render import render_assessment_result
from ics_assessment.result_models import AssessmentResult, CategoryResult, CheckResult


def test_render_assessment_result_compact_layout():
    result = AssessmentResult(
        addresses=["0xabc", "0xdef"],
        categories=[
            CategoryResult(
                name="Experience",
                min_score=5,
                max_score=8,
                checks=[
                    CheckResult("eth-staker", 6, True, "0xabc"),
                    CheckResult("csm-mainnet", 0, False),
                ],
                raw_score=9,
                final_score=8,
            ),
            CategoryResult(
                name="Humanity",
                min_score=4,
                max_score=8,
                checks=[CheckResult("human-passport-max", 8, True, "0xdef: 25.1")],
                raw_score=8,
                final_score=8,
            ),
        ],
        total_score=16,
        eligible=True,
    )

    rendered = render_assessment_result(result)

    assert "Assessment" in rendered
    assert "Addresses: 0xabc, 0xdef" in rendered
    assert "Eligible: YES" in rendered
    assert "Experience  8/8" in rendered
    assert "Proof of Experience  8/8  (raw 9, capped from max 8)" in rendered
    assert "Eth Staker   6  PASS" in rendered
    assert "0xabc" in rendered
    assert "Csm Mainnet  0  FAIL" in rendered
