from dataclasses import dataclass


@dataclass(frozen=True)
class CheckOutcome:
    score: float
    detail: str | None = None
    matched: bool | None = None

    def to_result(self, name: str) -> "CheckResult":
        matched = self.score > 0 if self.matched is None else self.matched
        return CheckResult(name=name, score=self.score, matched=matched, detail=self.detail)


@dataclass(frozen=True)
class CheckResult:
    name: str
    score: float
    matched: bool
    detail: str | None = None


@dataclass(frozen=True)
class CategoryResult:
    name: str
    min_score: int
    max_score: int
    checks: list[CheckResult]
    raw_score: float
    final_score: float


@dataclass(frozen=True)
class AssessmentResult:
    addresses: list[str]
    categories: list[CategoryResult]
    total_score: float
    eligible: bool

    def category(self, name: str) -> CategoryResult:
        for category in self.categories:
            if category.name == name:
                return category
        raise KeyError(name)
