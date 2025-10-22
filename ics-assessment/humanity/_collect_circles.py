import requests
from web3 import Web3

PROVIDER_URL_GNOSISCHAIN = "https://rpc.gnosis.gateway.fm"
GROUP_ADDRESS = "0xcfcea7904f42fd10e32703a57922e8d2036e3231"
GROUP_ABI = """[{"inputs": [], "name": "HUB", "outputs": [{"internalType": "address", "name": "", "type": "address"}], "stateMutability": "view", "type": "function"}]"""
GROUP_CREATION_BLOCK = 41502657
SAFE_ABI = """[{
    "inputs": [],
    "name": "getOwners",
    "outputs": [
      {
        "internalType": "address[]",
        "name": "",
        "type": "address[]"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }]"""

DEFAULT_SAFE_OWNER = "0xfD90FAd33ee8b58f32c00aceEad1358e4AFC23f9"
BASE_TREASURY_ADDRESS = "0x22c0bcb4758e583b30a4b4e5105925ec7b563f4e"

HUB_ABI = """[{
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "address",
        "name": "truster",
        "type": "address"
      },
      {
        "indexed": true,
        "internalType": "address",
        "name": "trustee",
        "type": "address"
      },
      {
        "indexed": false,
        "internalType": "uint256",
        "name": "expiryTime",
        "type": "uint256"
      }
    ],
    "name": "Trust",
    "type": "event"
  }]"""


def collect_trustees_rpc(w3):
    group_contract = w3.eth.contract(address=w3.to_checksum_address(GROUP_ADDRESS), abi=GROUP_ABI)
    hub_address = group_contract.functions.HUB().call()

    hub_contract = w3.eth.contract(address=w3.to_checksum_address(hub_address), abi=HUB_ABI)
    events = hub_contract.events.Trust.create_filter(
        fromBlock=GROUP_CREATION_BLOCK,
        argument_filters={'truster': w3.to_checksum_address(GROUP_ADDRESS)}
    ).get_all_entries()

    return set(event.args.trustee for event in events if event.args.trustee.lower() != BASE_TREASURY_ADDRESS.lower())



def collect_trustees_api():
    body = {
        "jsonrpc":"2.0",
        "id":20,
        "method":"circles_query",
        "params":
            [
                {"Namespace":"V_CrcV2",
                 "Table":"TrustRelations",
                 "Columns":["trustee"],
                 "Filter":[
                     {
                         "Type": "FilterPredicate",
                         "FilterType": "Equals",
                         "Column": "truster",
                         "Value": GROUP_ADDRESS
                     }],
                 "Order":[]
                 }
            ]
    }
    response = requests.post("https://rpc.aboutcircles.com/circles_query", json=body)
    return {row[0] for row in response.json()["result"]["rows"] if row[0].lower() != BASE_TREASURY_ADDRESS.lower()}


def collect_circles():
    w3 = Web3(Web3.HTTPProvider(PROVIDER_URL_GNOSISCHAIN))

    # trustees_rpc = collect_trustees_rpc(w3)

    trustees = collect_trustees_api()
    circle_addresses = set()
    for trustee in trustees:
        safe_contract = w3.eth.contract(address=Web3.to_checksum_address(trustee), abi=SAFE_ABI)
        trustee_owners = safe_contract.functions.getOwners().call()
        trustee_owners = filter(lambda x: x.lower() != DEFAULT_SAFE_OWNER.lower(), trustee_owners)
        circle_addresses.update(trustee_owners)


    print("Total circles collected:", len(trustees))
    with open("circle_group_members.csv", "w") as f:
        for addr in sorted(circle_addresses):
            f.write(f"{addr}\n")

if __name__ == '__main__':
    collect_circles()
