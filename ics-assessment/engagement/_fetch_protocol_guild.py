from collections import defaultdict

from web3 import Web3


RPC_URL = "http://localhost:8545"
PGVOTE_NFT_ADDRESS = "0x4a9cef2134Fa8e48ff2BeaF533D8b5E05e085Dc0"
FROM_BLOCK = 19620007  # created at
TO_BLOCK = 24293769  # cutoff date

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
TRANSFER_EVENT_ABI = [
    {
        "type": "event",
        "name": "Transfer",
        "inputs": [
            {"name": "from", "type": "address", "indexed": True},
            {"name": "to", "type": "address", "indexed": True},
            {"name": "value", "type": "uint256", "indexed": False},
        ],
        "anonymous": False,
    }
]


def fetch_erc20_balances(
    rpc: str,
    address: str,
    from_block: int,
    to_block: int,
) -> dict[str, int]:
    w3 = Web3(Web3.HTTPProvider(rpc))
    contract = w3.eth.contract(
        address=w3.to_checksum_address(address),
        abi=TRANSFER_EVENT_ABI,
    )

    logs = contract.events.Transfer.get_logs(
        from_block=from_block,
        to_block=to_block,
    )
    logs = sorted(
        logs,
        key=lambda log: (
            log["blockNumber"],
            log["transactionIndex"],
            log["logIndex"],
        ),
    )

    balances: defaultdict[str, int] = defaultdict(int)
    for log in logs:
        transfer = log["args"]
        from_addr = transfer["from"]
        to_addr = transfer["to"]
        value = int(transfer["value"])

        if from_addr != ZERO_ADDRESS:
            balances[from_addr] -= value
            if balances[from_addr] <= 0:
                del balances[from_addr]

        if to_addr != ZERO_ADDRESS:
            balances[to_addr] += value

    return dict(balances)


def fetch_erc20_holders(
    rpc: str,
    address: str,
    from_block: int,
    to_block: int,
) -> set[str]:
    balances = fetch_erc20_balances(rpc, address, from_block, to_block)
    return {addr for addr, balance in balances.items() if balance > 0}


def write_holders(path: str, holders: set[str]) -> None:
    with open(path, "w") as file:
        for address in sorted(holders):
            file.write(f"{address}\n")


if __name__ == "__main__":
    holders = fetch_erc20_holders(
        RPC_URL,
        PGVOTE_NFT_ADDRESS,
        FROM_BLOCK,
        TO_BLOCK,
    )
    write_holders("protocol_guild.csv", holders)
    print(
        f"Detected {len(holders)} holders between blocks {FROM_BLOCK} and {TO_BLOCK}"
    )
