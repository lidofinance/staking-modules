import sys

# Import the scoring functions from the engagement and experience modules
from engagement.main import (
    main as engagement_main,
    MIN_SCORE as ENG_MIN_SCORE,
    MAX_SCORE as ENG_MAX_SCORE,
)
from experience.main import (
    main as experience_main,
    MIN_SCORE as EXP_MIN_SCORE,
    MAX_SCORE as EXP_MAX_SCORE,
)
from humanity.main import (
    main as humanity_main,
    MIN_SCORE as HUM_MIN_SCORE,
    MAX_SCORE as HUM_MAX_SCORE,
)

def main():
    if len(sys.argv) < 2:
        print("Usage: python main.py <address1> [<address2> ...]")
        return

    addrs = set([a.strip().lower() for a in sys.argv[1:]])

    print("\n==== Proof of Experience ====")
    experience_score = experience_main(addrs)
    print("\n==== Proof of Humanity ====")
    humanity_score = humanity_main(addrs)
    print("==== Proof of Engagement ====")
    engagement_score = engagement_main(addrs)
    print("\n==== Assessment Completed ====")
    print(
        f"Total Experience Score: {experience_score} (limits: min={EXP_MIN_SCORE}, max={EXP_MAX_SCORE}) "
        + ("✅" if experience_score else "❌")
    )
    print(
        f"Total Humanity Score: {humanity_score} (limits: min={HUM_MIN_SCORE}, max={HUM_MAX_SCORE}) "
        + ("✅" if humanity_score else "❌")
    )
    print(
        f"Total Engagement Score: {engagement_score} (limits: min={ENG_MIN_SCORE}, max={ENG_MAX_SCORE}) "
        + ("✅" if engagement_score else "❌")
    )
    total = experience_score + humanity_score + engagement_score
    print(
        f"Sum of all scores: {total} (limits: min=15)" + (" ✅" if total >= 15 else " ❌")
    )

    # Final resolution summary
    print("\n==== Resolution ====")
    missing = []
    if not experience_score:
        missing.append("Experience")
    if not humanity_score:
        missing.append("Humanity")
    if not engagement_score:
        missing.append("Engagement")
    if total < 15:
        missing.append("Total")

    if not missing:
        print("✅ Eligible: minimum criteria met in all categories (Experience, Humanity, Engagement).")
    else:
        why = ", ".join(missing)
        print(f"❌ Not eligible: requirements not met in category(ies): {why}.")



if __name__ == "__main__":
    main()
