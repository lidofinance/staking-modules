import asyncio
import json
from types import SimpleNamespace

import pytest

from ics_assessment import sync
from ics_assessment.experience.assess import ExperienceEvaluator
from ics_assessment.experience.sources import ExperienceSources, load_owner_map

MANAGER = "0x368Da1891a15cc84bb91E672710bEA0B46CaC393"
REWARD = "0x81932353c285e5f47F7366fcdcaCbD1D49a0B02b"
STRANGER = "0x" + "ab" * 20


@pytest.fixture
def sources(tmp_path):
    result = ExperienceSources(
        data_dir=tmp_path,
        static_dir=tmp_path,
        circles_group_members_path=tmp_path / "circles.csv",
        eligible_addresses_holesky_path=tmp_path / "holesky.json",
        eligible_node_operators_hoodi_path=tmp_path / "hoodi-eligible.json",
        eligible_node_operators_mainnet_path=tmp_path / "mainnet-eligible.json",
        node_operator_owners_hoodi_path=tmp_path / "hoodi-owners.json",
        node_operator_owners_mainnet_path=tmp_path / "mainnet-owners.json",
    )
    result.eligible_addresses_holesky_path.write_text("[]")
    result.circles_group_members_path.write_text("")
    for chain in ("mainnet", "hoodi"):
        getattr(result, f"eligible_node_operators_{chain}_path").write_text('["583"]')
        getattr(result, f"node_operator_owners_{chain}_path").write_text(
            json.dumps(
                {
                    "583": [MANAGER, REWARD],
                }
            )
        )
    return result


@pytest.mark.parametrize("chain,points", [("mainnet", 6), ("hoodi", 4)])
@pytest.mark.parametrize("addresses", [{MANAGER}, {REWARD}, {MANAGER, REWARD}])
def test_both_management_roles_recognize_eligible_operator_once(
    sources, chain, points, addresses
):
    evaluator = ExperienceEvaluator(sources)
    assert (
        getattr(
            evaluator, f"_csm_{'testnet' if chain == 'hoodi' else 'mainnet'}_score"
        )(addresses)
        == points
    )


@pytest.mark.parametrize("chain", ["mainnet", "hoodi"])
def test_an_unrelated_address_does_not_inherit_operator_experience(sources, chain):
    evaluator = ExperienceEvaluator(sources)
    assert (
        getattr(
            evaluator, f"_csm_{'testnet' if chain == 'hoodi' else 'mainnet'}_score"
        )({STRANGER})
        == 0
    )


@pytest.mark.parametrize("chain", ["mainnet", "hoodi"])
def test_management_address_still_needs_operator_performance(sources, chain):
    getattr(sources, f"eligible_node_operators_{chain}_path").write_text("[]")
    evaluator = ExperienceEvaluator(sources)
    assert (
        getattr(
            evaluator, f"_csm_{'testnet' if chain == 'hoodi' else 'mainnet'}_score"
        )({MANAGER, REWARD})
        == 0
    )


def test_all_operator_ids_are_checked_for_a_shared_manager(sources):
    owners = {
        str(operator): [MANAGER, REWARD]
        for operator in (582, 583)
    }
    sources.node_operator_owners_mainnet_path.write_text(json.dumps(owners))
    assert ExperienceEvaluator(sources)._csm_mainnet_score({MANAGER}) == 6


@pytest.mark.parametrize("extended", [False, True])
@pytest.mark.parametrize("reward", [REWARD, MANAGER])
def test_sync_keeps_unique_addresses_regardless_of_extended_permissions(
    monkeypatch, tmp_path, extended, reward
):
    calls = []

    async def count_call(block_identifier):
        calls.append(block_identifier)
        return 1

    async def operator_call(block_identifier):
        calls.append(block_identifier)
        return SimpleNamespace(
            managerAddress=MANAGER,
            rewardAddress=reward,
            extendedManagerPermissions=extended,
        )

    async def disconnect():
        calls.append("disconnected")

    contract = SimpleNamespace(
        functions=SimpleNamespace(
            getNodeOperatorsCount=lambda: SimpleNamespace(call=count_call),
            getNodeOperator=lambda operator: SimpleNamespace(call=operator_call),
        )
    )

    class FakeAsyncWeb3:
        AsyncHTTPProvider = staticmethod(lambda url: url)

        def __init__(self, provider):
            self.eth = SimpleNamespace(contract=lambda **kwargs: contract)
            self.provider = SimpleNamespace(disconnect=disconnect)

    monkeypatch.setattr(sync.experience_jobs, "AsyncWeb3", FakeAsyncWeb3)
    path = tmp_path / "owners.json"
    asyncio.run(
        sync.experience_jobs._sync_node_operator_owners_one(
            "https://rpc.example", "contract", 25928919, path
        )
    )
    assert json.loads(path.read_text()) == {
        "0": sorted({MANAGER.lower(), reward.lower()})
    }
    assert load_owner_map(path) == {"0": {MANAGER.lower(), reward.lower()}}
    assert calls == [25928919, 25928919, "disconnected"]


@pytest.mark.parametrize("old_value", [REWARD, {"managerAddress": MANAGER, "rewardAddress": REWARD}])
def test_old_owner_maps_require_resync(tmp_path, old_value):
    path = tmp_path / "owners.json"
    path.write_text(json.dumps({"583": old_value}))
    with pytest.raises(ValueError, match="sync node-owners"):
        load_owner_map(path)
