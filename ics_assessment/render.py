from ics_assessment.result_models import AssessmentResult, CategoryResult, CheckResult


RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[32m"
RED = "\033[31m"
CYAN = "\033[36m"
YELLOW = "\033[33m"


def _format_score(value: float) -> str:
    if value == int(value):
        return str(int(value))
    return str(value)


def _format_label(name: str) -> str:
    return name.replace("-", " ").title()


def _format_addresses(addresses: set[str] | list[str]) -> str:
    if isinstance(addresses, set):
        return ", ".join(sorted(addresses))
    return ", ".join(addresses)


def _style(text: str, *codes: str, enabled: bool) -> str:
    if not enabled:
        return text
    return "".join(codes) + text + RESET


def _status_text(matched: bool, styled: bool) -> str:
    if matched:
        return _style("PASS ✓", GREEN, enabled=styled)
    return _style("FAIL ✗", RED, enabled=styled)


def _render_check(check: CheckResult, label_width: int, score_width: int, styled: bool) -> list[str]:
    label = _format_label(check.name)
    score = _format_score(check.score)
    status = _status_text(check.matched, styled)
    lines = [f"  {label:<{label_width}}  {score:>{score_width}}  {status}"]
    if check.detail:
        lines.append(f"    {_style(check.detail, DIM, enabled=styled)}")
    return lines


def _render_category_header(result: CategoryResult, styled: bool) -> str:
    score = _format_score(result.final_score)
    max_score = _format_score(result.max_score)
    raw_score = _format_score(result.raw_score)
    if result.raw_score > result.max_score:
        note = f"raw {raw_score}, capped from max {max_score}"
    elif result.final_score < result.min_score:
        note = f"raw {raw_score}, below min {result.min_score}"
    else:
        note = f"raw {raw_score}"
    return (
        f"{_style(f'Proof of {result.name}', BOLD, CYAN, enabled=styled)}  "
        f"{_style(f'{score}/{max_score}', BOLD, enabled=styled)}  "
        f"{_style(f'({note})', YELLOW, enabled=styled)}"
    )


def render_category_result(
    result: CategoryResult,
    addresses: set[str] | list[str],
    *,
    styled: bool = False,
) -> str:
    label_width = max(len(_format_label(check.name)) for check in result.checks)
    score_width = max(len(_format_score(check.score)) for check in result.checks)
    lines = [
        f"{_style('Addresses:', BOLD, enabled=styled)} {_format_addresses(addresses)}",
        _render_category_header(result, styled),
        "",
    ]
    for check in result.checks:
        lines.extend(_render_check(check, label_width, score_width, styled))
    return "\n".join(lines)


def render_assessment_result(result: AssessmentResult, *, styled: bool = False) -> str:
    eligible_text = (
        _style("YES ✓", GREEN, BOLD, enabled=styled)
        if result.eligible
        else _style("NO ✗", RED, BOLD, enabled=styled)
    )
    lines = [
        _style("Assessment", BOLD, CYAN, enabled=styled),
        f"{_style('Addresses:', BOLD, enabled=styled)} {_format_addresses(result.addresses)}",
        f"{_style('Total:', BOLD, enabled=styled)} {_format_score(result.total_score)}",
        f"{_style('Eligible:', BOLD, enabled=styled)} {eligible_text}",
        "",
    ]
    for category in result.categories:
        lines.append(
            f"{_style(category.name + ':', BOLD, enabled=styled):<20} "
            f"{_format_score(category.final_score)}/{_format_score(category.max_score)}"
        )
    lines.append("")

    for index, category in enumerate(result.categories):
        lines.append(_render_category_header(category, styled))
        label_width = max(len(_format_label(check.name)) for check in category.checks)
        score_width = max(len(_format_score(check.score)) for check in category.checks)
        for check in category.checks:
            lines.extend(_render_check(check, label_width, score_width, styled))
        if index != len(result.categories) - 1:
            lines.append("")
    return "\n".join(lines)
