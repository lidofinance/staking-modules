type FramePerfLog = {
  blockstamp: {
    state_root: `0x${string}`;
    slot_number: number;
    block_hash: `0x${string}`;
    block_number: number;
    block_timestamp: number;
    ref_slot: number;
    ref_epoch: number;
  };
  frame: [number, number];
  distributable: bigint;
  distributed_rewards: bigint;
  rebate_to_protocol: bigint;
  operators: {
    [operatorId: string]: {
      distributed_rewards: bigint;
      performance_coefficients: {
        attestations_weight: number;
        blocks_weight: number;
        sync_weight: number;
      };
      validators: {
        [validatorId: string]: {
          distributed_rewards: bigint;
          performance: number;
          threshold: number;
          reward_share: number;
          participation_share_multiplier: number;
          slashed: boolean;
          strikes: number;
          attestation_duty: {
            assigned: number;
            included: number;
          };
          proposal_duty: {
            assigned: number;
            included: number;
          };
          sync_duty: {
            assigned: number;
            included: number;
          };
        };
      };
    };
  };
};
