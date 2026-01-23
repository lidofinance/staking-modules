import json
import asyncio
from web3 import AsyncWeb3

PROVIDER_URL_MAINNET = 'http://localhost:8545/'
PROVIDER_URL_HOODI = 'http://localhost:8545/'
CONTRACT_ADDRESS_MAINNET = '0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F'
CONTRACT_ADDRESS_HOODI = '0x79CEf36D84743222f37765204Bec41E92a93E59d'

with open("../../artifacts/mainnet/ics/abi/csm_abi.json", "r") as file:
    CSM_ABI = file.read()

REFERENCE_BLOCK_MAINNET = 24293769
REFERENCE_BLOCK_HOODI = 2086013

OUTPUT_FILE_MAINNET = 'node_operator_owners_mainnet.json'
OUTPUT_FILE_HOODI = 'node_operator_owners_hoodi.json'


async def fetch_node_operator_owners(provider_url, contract_address, reference_block, json_output):
    w3 = AsyncWeb3(AsyncWeb3.AsyncHTTPProvider(provider_url))
    contract = w3.eth.contract(address=contract_address, abi=CSM_ABI, decode_tuples=True)

    node_operators = {}
    count = await contract.functions.getNodeOperatorsCount().call(block_identifier=reference_block)

    queue = asyncio.Queue()
    for i in range(count):
        await queue.put(i)

    processed = {"num": 0}

    async def worker():
        while True:
            try:
                i = queue.get_nowait()
            except asyncio.QueueEmpty:
                break
            node_operator = await contract.functions.getNodeOperator(i).call(block_identifier=reference_block)
            node_operators[i] = node_operator.managerAddress if node_operator.extendedManagerPermissions else node_operator.rewardAddress
            processed["num"] += 1
            if processed["num"] % 10 == 0 or processed["num"] == count:
                print(f"Fetched {processed['num']}/{count} node operators.")

            queue.task_done()

    workers = [asyncio.create_task(worker()) for _ in range(4)]  # 4 concurrent workers
    await queue.join()
    for w in workers:
        w.cancel()

    with open(json_output, 'w') as f:
        json.dump(dict(sorted(node_operators.items(), key=lambda item: item[0])), f, indent=2)


if __name__ == '__main__':
    asyncio.run(fetch_node_operator_owners(PROVIDER_URL_MAINNET, CONTRACT_ADDRESS_MAINNET, REFERENCE_BLOCK_MAINNET, OUTPUT_FILE_MAINNET))
    asyncio.run(fetch_node_operator_owners(PROVIDER_URL_HOODI, CONTRACT_ADDRESS_HOODI, REFERENCE_BLOCK_HOODI, OUTPUT_FILE_HOODI))