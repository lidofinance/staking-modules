import json
from web3 import Web3

PROVIDER_URL_MAINNET = "http://localhost:8545"  # Replace with your actual Web3 provider URL
CONTRACT_ADDRESS_MAINNET = '0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F'

with open("abi/csm_abi.json", "r") as file:
    CSM_ABI = file.read()

REFERENCE_BLOCK_MAINNET = 22845716
ICS_ROUNDS = 3

exclude_files = [
    "exclude/allnodes.json",
    "exclude/associated_operators.json",
    "exclude/bad_performers.json",
    "exclude/inactive.json",
    "exclude/pros.json",
    "exclude/ssv_delegated.json",
    "exclude/self_exclusion.json",
]

def main():
    # read all exclude files
    exclude = set()
    for file_path in exclude_files:
        with open(file_path, 'r') as f:
            data = json.load(f)
            exclude.update(data)

    with open("sources/ea.json", "r") as f:
        ea_nos = set(json.load(f))

    print(f"Total Node Operators in EA: {len(ea_nos)}")
    # filter out excluded nos
    filtered_nos = ea_nos - exclude
    print(f"Filtered Node Operators (excluding {len(exclude)}): {len(filtered_nos)}")

    ics_addresses = []

    for i in range(ICS_ROUNDS):
        with open(f"sources/ics_assessment_{i+1}.json", "r") as f:
            ics_addresses.append(json.load(f))
        print(f"Total ICS Round {i+1} Addresses: {len(ics_addresses[i])}")


    w3 = Web3(Web3.HTTPProvider(PROVIDER_URL_MAINNET))
    contract = w3.eth.contract(address=CONTRACT_ADDRESS_MAINNET, abi=CSM_ABI, decode_tuples=True)

    final_addresses = []
    for no_id in filtered_nos:
        node_operator = contract.functions.getNodeOperator(no_id).call(block_identifier=REFERENCE_BLOCK_MAINNET)
        no_address = node_operator.managerAddress if node_operator.extendedManagerPermissions else node_operator.rewardAddress
        final_addresses.append(no_address)
        print(f"Node Operator ID: {no_id}, Address: {no_address}")

    for i in range(ICS_ROUNDS):
        ics_round_addresses = ics_addresses[i]
        print(f"Adding {len(ics_round_addresses)} addresses from ICS Round {i+1}")
        for addr in ics_round_addresses:
            final_addresses.append(addr)

    final_addresses_set = set(final_addresses)
    with open("ics.csv", "w") as f:
        for address in sorted(final_addresses_set):
            f.write(f"{address}\n")

if __name__ == '__main__':
    main()
