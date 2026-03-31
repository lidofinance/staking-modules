import csv
from collections import defaultdict

import requests
from web3 import Web3

from ics_assessment.config import (
    ARAGON_REQUIRED_LDO,
    ARAGON_VOTERS_PATH,
    ARAGON_VOTING_ADDRESS,
    ARAGON_VOTING_DEPLOYMENT_BLOCK,
    GALXE_API_URL,
    GALXE_LOYALTY_POINTS_PATH,
    GALXE_SPACE_ID,
    GITPOAP_API_URL,
    GITPOAP_EVENTS_PATH,
    GITPOAP_HOLDERS_PATH,
    MAINNET_RPC_URL,
    MAINNET_CUTOFF_BLOCK,
    PROTOCOL_GUILD_FROM_BLOCK,
    PROTOCOL_GUILD_NFT_ADDRESS,
    PROTOCOL_GUILD_PATH,
    REQUIRED_SNAPSHOT_VP,
    SNAPSHOT_SPACE,
    SNAPSHOT_VOTE_TIMESTAMP,
    SNAPSHOT_VOTERS_PATH,
    ZERO_ADDRESS,
)
from ics_assessment.sync import ARAGON_ABI, TRANSFER_EVENT_ABI, get_event_logs, write_csv, write_lines


def sync_aragon() -> None:
    w3 = Web3(Web3.HTTPProvider(MAINNET_RPC_URL))
    contract = w3.eth.contract(
        address=Web3.to_checksum_address(ARAGON_VOTING_ADDRESS),
        abi=ARAGON_ABI,
        decode_tuples=True,
    )
    logs = get_event_logs(
        contract.events.CastVote(),
        ARAGON_VOTING_DEPLOYMENT_BLOCK,
        MAINNET_CUTOFF_BLOCK,
        label="Aragon CastVote",
    )

    voters: defaultdict[str, set[int]] = defaultdict(set)
    for log in logs:
        if log.args.stake >= ARAGON_REQUIRED_LDO:
            voters[log.args.voter.lower()].add(int(log.args.voteId))

    rows = [[address, len(vote_ids)] for address, vote_ids in sorted(voters.items())]
    write_csv(ARAGON_VOTERS_PATH, ["Address", "VoteCount"], rows)
    print(f"Wrote {len(rows)} Aragon voters to {ARAGON_VOTERS_PATH}")


def sync_snapshot() -> None:
    query = """
    query Votes($created_lt: Int!) {
      votes(
        first: 1000
        where: {
          space: "%s"
          vp_gt: %s
          created_lt: $created_lt
        }
        orderBy: "created"
        orderDirection: desc
      ) {
        voter
        id
        created
      }
    }
    """ % (SNAPSHOT_SPACE, REQUIRED_SNAPSHOT_VP)

    counts: defaultdict[str, int] = defaultdict(int)
    created_lt = SNAPSHOT_VOTE_TIMESTAMP
    seen_vote_ids: set[str] = set()
    while True:
        response = requests.post(
            "https://hub.snapshot.org/graphql",
            json={"query": query, "variables": {"created_lt": created_lt}},
        )
        response.raise_for_status()
        data = response.json()
        if "errors" in data:
            raise RuntimeError(f"Snapshot sync failed: {data['errors']}")
        votes = data["data"]["votes"]
        if not votes:
            break
        next_created_lt = min(int(vote["created"]) for vote in votes)
        for vote in votes:
            vote_id = vote["id"]
            if vote_id in seen_vote_ids:
                continue
            seen_vote_ids.add(vote_id)
            counts[vote["voter"].lower()] += 1
        if next_created_lt >= created_lt:
            raise RuntimeError("Snapshot sync cursor did not advance")
        created_lt = next_created_lt

    rows = [[address, count] for address, count in sorted(counts.items())]
    write_csv(SNAPSHOT_VOTERS_PATH, ["Address", "VoteCount"], rows)
    print(f"Wrote {len(rows)} Snapshot voters to {SNAPSHOT_VOTERS_PATH}")


def sync_galxe() -> None:
    query = """
    query($spaceId: Int, $cursor: String) {
      space(id:$spaceId) {
        loyaltyPointsRanks(first:100,cursorAfter:$cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          edges {
            node {
              points
              address {
                address
              }
            }
          }
        }
      }
    }
    """

    cursor = None
    rows: list[list[str | int]] = []
    while True:
        response = requests.post(
            GALXE_API_URL,
            json={"query": query, "variables": {"spaceId": GALXE_SPACE_ID, "cursor": cursor}},
            headers={"Content-Type": "application/json"},
        )
        response.raise_for_status()
        data = response.json()["data"]["space"]["loyaltyPointsRanks"]
        for edge in data["edges"]:
            node = edge["node"]
            rows.append([node["address"]["address"].lower(), int(node["points"])])
        if not data["pageInfo"]["hasNextPage"]:
            break
        cursor = data["pageInfo"]["endCursor"]

    rows.sort(key=lambda row: row[0])
    write_csv(GALXE_LOYALTY_POINTS_PATH, ["Address", "Points"], rows)
    print(f"Wrote {len(rows)} Galxe rows to {GALXE_LOYALTY_POINTS_PATH}")


def sync_gitpoap() -> None:
    with GITPOAP_EVENTS_PATH.open("r", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        events = [(row["ID"], row["Name"]) for row in reader]

    session = requests.Session()
    session.mount("https://", requests.adapters.HTTPAdapter(max_retries=3))

    rows: list[list[str | int]] = []
    for event_id, event_name in events:
        response = session.get(f"{GITPOAP_API_URL}/gitpoaps/{event_id}/addresses")
        response.raise_for_status()
        for address in sorted({addr.lower() for addr in response.json().get("addresses", [])}):
            rows.append([address, event_id, event_name])

    rows.sort(key=lambda row: (row[0], str(row[1])))
    write_csv(GITPOAP_HOLDERS_PATH, ["Address", "EventID", "EventName"], rows)
    print(f"Wrote {len(rows)} GitPOAP rows to {GITPOAP_HOLDERS_PATH}")


def sync_protocol_guild() -> None:
    w3 = Web3(Web3.HTTPProvider(MAINNET_RPC_URL))
    contract = w3.eth.contract(
        address=w3.to_checksum_address(PROTOCOL_GUILD_NFT_ADDRESS),
        abi=TRANSFER_EVENT_ABI,
    )
    logs = get_event_logs(
        contract.events.Transfer,
        PROTOCOL_GUILD_FROM_BLOCK,
        MAINNET_CUTOFF_BLOCK,
        label="Protocol Guild Transfer",
    )
    logs = sorted(
        logs,
        key=lambda log: (log["blockNumber"], log["transactionIndex"], log["logIndex"]),
    )

    balances: defaultdict[str, int] = defaultdict(int)
    for log in logs:
        transfer = log["args"]
        from_addr = transfer["from"].lower()
        to_addr = transfer["to"].lower()
        value = int(transfer["value"])

        if from_addr != ZERO_ADDRESS:
            balances[from_addr] -= value
            if balances[from_addr] <= 0:
                del balances[from_addr]
        if to_addr != ZERO_ADDRESS:
            balances[to_addr] += value

    write_lines(PROTOCOL_GUILD_PATH, [addr for addr, balance in balances.items() if balance > 0])
    print(f"Wrote {len(balances)} Protocol Guild holders to {PROTOCOL_GUILD_PATH}")
