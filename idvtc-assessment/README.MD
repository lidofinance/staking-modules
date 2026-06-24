# IDVTC assessment script

Simple set of scripts to assess the IDVTC clusters for eligibility for approval.

## Requirements

- Python 3.10+

## Usage

### Update the approved clusters JSON file from the CSV file:

```bash
python idvtc.py update
```

### Assess a cluster for approval:

```bash
python idvtc.py check <main_address> <member1> <member2> <member3> <member4>
```

### Assess all clusters in the CSV file for approval:

```bash
python idvtc.py batch
```
