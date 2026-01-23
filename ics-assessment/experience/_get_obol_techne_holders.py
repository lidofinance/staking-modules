from web3 import Web3

ARBITRUM_BLOCK_CUTOFF = 424199696
ETHEREUM_BLOCK_CUTOFF = 24293769

# Preferably use infura for unlimited block range
ARBITRUM_PROVIDER_URL = 'http://localhost:8545/'
ETHEREUM_PROVIDER_URL = 'http://localhost:8545/'

def fetch_nft_holders(rpc: str, address: str, from_block: int, to_block: int) -> set:
    w3 = Web3(Web3.HTTPProvider(rpc))
    contract = w3.eth.contract(address=w3.to_checksum_address(address), abi=[{
        "type": "event",
        "name": "Transfer",
        "inputs": [
            {"name": "from", "type": "address", "indexed": True},
            {"name": "to", "type": "address", "indexed": True},
            {"name": "tokenId", "type": "uint256", "indexed": True}
        ],
        "anonymous": False
    }])

    logs = contract.events.Transfer.get_logs(from_block=from_block, to_block=to_block)
    holders = set()
    for log in logs:
        holders.add(log.args.to)
    return holders

if __name__ == '__main__':
    obol_techne_base = fetch_nft_holders(
        ARBITRUM_PROVIDER_URL,
        "0x3cbBcc4381E0812F89175798AE7be2F47bC22021",
        from_block=182715383,
        to_block=ARBITRUM_BLOCK_CUTOFF
    )
    print(f"Found {len(obol_techne_base)} Obol Techne Base holders.")
    with open("obol-techne-credentials-base.csv", "w") as f:
        for holder in sorted(obol_techne_base):
            f.write(f"{holder}\n")

    obol_techne_bronze = fetch_nft_holders(
        ARBITRUM_PROVIDER_URL,
        "0x88Cb2eFFB9301138216368caf69c146E0A65374F",
        from_block=223252032,
        to_block=ARBITRUM_BLOCK_CUTOFF
    )
    print(f"Found {len(obol_techne_bronze)} Obol Techne Bronze holders.")
    with open("obol-techne-credentials-bronze.csv", "w") as f:
        for holder in sorted(obol_techne_bronze):
            f.write(f"{holder}\n")

    obol_techne_silver = fetch_nft_holders(
        ETHEREUM_PROVIDER_URL,
        "0xfdb3986f0c97c3c92af3c318d7d2742d8f7ed8cc",
        from_block=20162760,
        to_block=ETHEREUM_BLOCK_CUTOFF
    )
    print(f"Found {len(obol_techne_silver)} Obol Techne Silver holders.")
    with open("obol-techne-credentials-silver.csv", "w") as f:
        for holder in sorted(obol_techne_silver):
            f.write(f"{holder}\n")
