import os
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# Campaign cutoffs and windows.
MAINNET_CUTOFF_BLOCK = 24874303
HOODI_CUTOFF_BLOCK = 2612667
ARBITRUM_CUTOFF_BLOCK = 452226520
GNOSIS_CUTOFF_BLOCK = 45661118

SNAPSHOT_VOTE_TIMESTAMP = 1776117600

HIGH_SIGNAL_START_DATE = datetime(2025, 9, 1)
HIGH_SIGNAL_END_DATE = datetime(2026, 4, 14)

REQUIRED_PERFORMANCE_WINDOW_HOODI = 53
MAINNET_PERFORMANCE_REPORT_CIDS = [
    "QmcE3Ri6h5S6H5sNHoW94Jvvs2BmcPyffrZvtZGLg9Y6uD",
    "QmQtLXNxRzZZfNXeWB2vUqVzfPEQiBSj65AgJ2VaFqYW9P",
]


# Network endpoints.
MAINNET_RPC_URL = os.getenv("MAINNET_RPC_URL")
HOODI_RPC_URL = os.getenv("HOODI_RPC_URL")
ARBITRUM_RPC_URL = os.getenv("ARBITRUM_RPC_URL")
MAINNET_ARCHIVE_RPC_URL = os.getenv("MAINNET_ARCHIVE_RPC_URL", MAINNET_RPC_URL or "")
HOODI_ARCHIVE_RPC_URL = os.getenv("HOODI_ARCHIVE_RPC_URL", HOODI_RPC_URL or "")
GNOSIS_RPC_URL = "https://rpc.gnosis.gateway.fm"


# Category scoring policy.
ENGAGEMENT_SCORES = {
    "snapshot-vote": 1,
    "aragon-vote": 2,
    "galxe-score-4-10": 4,
    "galxe-score-above-10": 5,
    "git-poap": 2,
    "high-signal-30": 2,
    "high-signal-40": 3,
    "high-signal-60": 4,
    "high-signal-80": 5,
}
ENGAGEMENT_MIN_SCORE = 2
ENGAGEMENT_MAX_SCORE = 7

EXPERIENCE_SCORES = {
    "eth-staker": 6,
    "stake-cat": 6,
    "obol-techne-base": 4,
    "obol-techne-bronze": 5,
    "obol-techne-silver": 6,
    "ssv-verified": 7,
    "csm-testnet": 4,
    "csm-testnet-circles-verified": 5,
    "csm-mainnet": 6,
    "sdvtm-testnet": 5,
    "sdvtm-mainnet": 7,
}
EXPERIENCE_MIN_SCORE = 5
EXPERIENCE_MAX_SCORE = 8

HUMANITY_SCORES = {
    "human-passport-min": 3,
    "human-passport-max": 8,
    "circles-verified": 4,
    "discord-account": 2,
    "x-account": 1,
}
HUMANITY_MIN_SCORE = 4
HUMANITY_MAX_SCORE = 8


# Source configuration and onchain addresses.
ARAGON_VOTING_ADDRESS = "0x2e59A20f205bB85a89C53f1936454680651E618e"
ARAGON_VOTING_DEPLOYMENT_BLOCK = 11473216
ARAGON_REQUIRED_LDO = 100 * 10**18
REQUIRED_ARAGON_VOTES = 2

SNAPSHOT_SPACE = "lido-snapshot.eth"
REQUIRED_SNAPSHOT_VOTES = 3
REQUIRED_SNAPSHOT_VP = 100

GALXE_API_URL = "https://graphigo.prd.galaxy.eco/query"
GALXE_SPACE_ID = 22849

GITPOAP_API_URL = "https://public-api.gitpoap.io/v1"
SSV_OPERATORS_API_URL = (
    "https://api.ssv.network/api/v4/mainnet/operators"
    "?type=verified_operator&page=1&perPage=1000"
)

PROTOCOL_GUILD_NFT_ADDRESS = "0x4a9cef2134Fa8e48ff2BeaF533D8b5E05e085Dc0"
PROTOCOL_GUILD_FROM_BLOCK = 19620007
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

HUMAN_PASSPORT_SCORER_ID = 11737
HUMAN_PASSPORT_API_URL = "https://api.passport.xyz/v2/stamps/{scorer_id}/score/{address}"

GROUP_ADDRESS = "0xcfcea7904f42fd10e32703a57922e8d2036e3231"
GROUP_CREATION_BLOCK = 41502657
DEFAULT_SAFE_OWNER = "0xfD90FAd33ee8b58f32c00aceEad1358e4AFC23f9"
BASE_TREASURY_ADDRESS = "0x22c0bcb4758e583b30a4b4e5105925ec7b563f4e"

CSM_MAINNET_ADDRESS = "0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F"
CSM_HOODI_ADDRESS = "0x79CEf36D84743222f37765204Bec41E92a93E59d"
HOODI_FEE_DISTRIBUTOR_ADDRESS = "0xaCd9820b0A2229a82dc1A0770307ce5522FF3582"
HOODI_FEE_DISTRIBUTOR_FROM_BLOCK = 4980


# Package and data paths.
ROOT_DIR = Path(__file__).parent.resolve()
ENGAGEMENT_DIR = ROOT_DIR / "engagement"
EXPERIENCE_DIR = ROOT_DIR / "experience"
HUMANITY_DIR = ROOT_DIR / "humanity"
ENGAGEMENT_DATA_DIR = ENGAGEMENT_DIR / "data"
EXPERIENCE_DATA_DIR = EXPERIENCE_DIR / "data"
EXPERIENCE_STATIC_DIR = EXPERIENCE_DIR / "static"
HUMANITY_DATA_DIR = HUMANITY_DIR / "data"

# Batch processing paths.
BATCH_FORMS_PATH = ROOT_DIR / "ics-forms.csv"
BATCH_LOGS_DIR = ROOT_DIR / "logs"
BATCH_APPROVED_ADDRESS_SUMMARY_PATH = ROOT_DIR / "approved-address-summary.json"

# Synced artifact locations.
ARAGON_VOTERS_PATH = ENGAGEMENT_DATA_DIR / "aragon_voters.csv"
SNAPSHOT_VOTERS_PATH = ENGAGEMENT_DATA_DIR / "snapshot_voters.csv"
GALXE_LOYALTY_POINTS_PATH = ENGAGEMENT_DATA_DIR / "galxe_loyalty_points.csv"
GITPOAP_HOLDERS_PATH = ENGAGEMENT_DATA_DIR / "gitpoap_holders.csv"
GITPOAP_EVENTS_PATH = ENGAGEMENT_DATA_DIR / "gitpoap_events.csv"
PROTOCOL_GUILD_PATH = ENGAGEMENT_DATA_DIR / "protocol_guild.csv"

NODE_OPERATOR_OWNERS_MAINNET_PATH = EXPERIENCE_DATA_DIR / "node_operator_owners_mainnet.json"
NODE_OPERATOR_OWNERS_HOODI_PATH = EXPERIENCE_DATA_DIR / "node_operator_owners_hoodi.json"
ELIGIBLE_NODE_OPERATORS_MAINNET_PATH = EXPERIENCE_DATA_DIR / "eligible_node_operators_mainnet.json"
ELIGIBLE_NODE_OPERATORS_HOODI_PATH = EXPERIENCE_DATA_DIR / "eligible_node_operators_hoodi.json"
ELIGIBLE_ADDRESSES_HOLESKY_PATH = EXPERIENCE_STATIC_DIR / "eligible_addresses_holesky.json"
SSV_VERIFIED_OPERATORS_PATH = EXPERIENCE_DATA_DIR / "ssv-verified-operators.csv"

CIRCLE_GROUP_MEMBERS_PATH = HUMANITY_DATA_DIR / "circle_group_members.csv"


# Credential sync specs.
OBOL_TECHNE_CREDENTIALS = [
    {
        "name": "base",
        "rpc_url": ARBITRUM_RPC_URL,
        "contract_address": "0x3cbBcc4381E0812F89175798AE7be2F47bC22021",
        "from_block": 182715383,
        "to_block": ARBITRUM_CUTOFF_BLOCK,
        "output_path": EXPERIENCE_DATA_DIR / "obol-techne-credentials-base.csv",
    },
    {
        "name": "bronze",
        "rpc_url": ARBITRUM_RPC_URL,
        "contract_address": "0x88Cb2eFFB9301138216368caf69c146E0A65374F",
        "from_block": 223252032,
        "to_block": ARBITRUM_CUTOFF_BLOCK,
        "output_path": EXPERIENCE_DATA_DIR / "obol-techne-credentials-bronze.csv",
    },
    {
        "name": "silver",
        "rpc_url": MAINNET_RPC_URL,
        "contract_address": "0xfdb3986f0c97c3c92af3c318d7d2742d8f7ed8cc",
        "from_block": 20162760,
        "to_block": MAINNET_CUTOFF_BLOCK,
        "output_path": EXPERIENCE_DATA_DIR / "obol-techne-credentials-silver.csv",
    },
]
