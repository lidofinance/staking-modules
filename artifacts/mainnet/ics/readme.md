# Initial ICS list

Data collected as of block 22845716, July 4, 2025, using the [following](https://research.lido.fi/t/community-staking-module/5917/139#p-21934-conversion-of-ea-node-operators-to-ics-node-operators-4) methodology.

Initial list consists of the current EA members excluding the following categories:
- Pro Node Operators
- Inactive Node Operators
- Bad performers
- Associated node operators
- SSV delegated

Steps to reproduce the list:
- Ensure all sources are correct and up-to-date
- To update bad performers exclude list, run `bad_performers.py` script
- To update inactive node operators exclude list, run `inactive_operators.py` script
- To generate final list, run `main.py` script
- To compose the Merkle tree, run `compose.js` script
