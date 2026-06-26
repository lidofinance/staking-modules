import json

IDVTC_ROUNDS = 1

def main():
    final_addresses = []
    for i in range(IDVTC_ROUNDS):
        with open(f"sources/idvtc_assessment_{i+1}.json", "r") as f:
            idvtc_round_addresses = json.load(f)
        print(f"Adding {len(idvtc_round_addresses)} addresses from IDVTC Round {i+1}")
        for addr in idvtc_round_addresses:
            final_addresses.append(addr)

    final_addresses_set = set(final_addresses)
    with open("idvtc.csv", "w") as f:
        for address in sorted(final_addresses_set):
            f.write(f"{address}\n")

if __name__ == '__main__':
    main()
