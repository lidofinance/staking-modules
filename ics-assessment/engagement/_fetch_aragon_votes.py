from collections import defaultdict

from web3 import Web3

RPC_URL = "http://localhost:8545/"
ARAGON_BLOCK_CUTOFF = 24293769
REQUIRED_LDO = 100 * 10 ** 18  # 100 LDO in wei

if __name__ == '__main__':
    w3 = Web3(Web3.HTTPProvider(RPC_URL))

    voting_address = Web3.to_checksum_address("0x2e59A20f205bB85a89C53f1936454680651E618e")
    voting_deployment_block = 11473216

    # event CastVote(uint256 indexed voteId, address indexed voter, bool supports, uint256 stake);
    abi = '[{"anonymous":false,"inputs":[{"indexed":true,"name":"voteId","type":"uint256"},{"indexed":true,"name":"voter","type":"address"},{"indexed":false,"name":"supports","type":"bool"},{"indexed":false,"name":"stake","type":"uint256"}],"name":"CastVote","type":"event"}]'
    contract = w3.eth.contract(address=voting_address, abi=abi, decode_tuples=True)
    logs = contract.events.CastVote().get_logs(
            from_block=voting_deployment_block,
            to_block=ARAGON_BLOCK_CUTOFF
    )

    voters = defaultdict(set)
    for log in logs:
        # filter out votes with less than required LDO
        if log.args.stake >= REQUIRED_LDO:
            voters[log.args.voter.lower()].add(log.args.voteId)

    with open("aragon_voters.csv", "w") as f:
        f.write("Address,VoteCount\n")
        for address, vote_ids in voters.items():
            f.write(f"{address},{len(vote_ids)}\n")
