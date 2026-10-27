from web3 import Web3

from ics_assessment.config import (
    BASE_TREASURY_ADDRESS,
    CIRCLE_GROUP_MEMBERS_PATH,
    DEFAULT_SAFE_OWNER,
    GNOSIS_RPC_URL,
    GNOSIS_CUTOFF_BLOCK,
    GROUP_ADDRESS,
    GROUP_CREATION_BLOCK,
)
from ics_assessment.sync import (
    GROUP_ABI,
    HUB_ABI,
    SAFE_ABI,
    get_event_logs,
    write_lines,
)


def sync_circles() -> None:
    w3 = Web3(Web3.HTTPProvider(GNOSIS_RPC_URL))
    group_contract = w3.eth.contract(
        address=w3.to_checksum_address(GROUP_ADDRESS),
        abi=GROUP_ABI,
    )
    hub_address = group_contract.functions.HUB().call(
        block_identifier=GNOSIS_CUTOFF_BLOCK
    )
    hub_contract = w3.eth.contract(address=w3.to_checksum_address(hub_address), abi=HUB_ABI)
    events = get_event_logs(
        hub_contract.events.Trust(),
        GROUP_CREATION_BLOCK,
        GNOSIS_CUTOFF_BLOCK,
        label="Circles Trust",
        argument_filters={"truster": w3.to_checksum_address(GROUP_ADDRESS)},
    )
    trustees = {
        event.args.trustee
        for event in events
        if event.args.trustee.lower() != BASE_TREASURY_ADDRESS.lower()
    }

    circle_addresses: set[str] = set()
    for trustee in trustees:
        safe_contract = w3.eth.contract(address=Web3.to_checksum_address(trustee), abi=SAFE_ABI)
        owners = safe_contract.functions.getOwners().call(
            block_identifier=GNOSIS_CUTOFF_BLOCK
        )
        for owner in owners:
            if owner.lower() != DEFAULT_SAFE_OWNER.lower():
                circle_addresses.add(owner.lower())

    write_lines(CIRCLE_GROUP_MEMBERS_PATH, circle_addresses)
    print(f"Wrote {len(circle_addresses)} circle group members to {CIRCLE_GROUP_MEMBERS_PATH}")
