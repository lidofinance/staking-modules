// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script, console } from "forge-std/Script.sol";

import { IFeeOracle } from "src/interfaces/IFeeOracle.sol";

import { DeploymentFixtures } from "test/helpers/Fixtures.sol";

import { ForkHelpersCommon } from "./Common.sol";

contract OracleReport is Script, DeploymentFixtures, ForkHelpersCommon {
    function submitRewards() external {
        _setUp();

        // Read oracle-report-data.json
        string memory artifactsDir = vm.envOr("ARTIFACTS_DIR", string("./artifacts/local/"));
        string memory json = vm.readFile(string.concat(artifactsDir, "rewards/oracle-report-data.json"));
        bytes32 root = vm.parseJsonBytes32(json, ".treeRoot");

        if (root == bytes32(0)) {
            console.log("Empty rewards report (zero treeRoot); skipping submission");
            return;
        }

        string memory treeCid = vm.parseJsonString(json, ".treeCid");
        string memory logCid = vm.parseJsonString(json, ".logCid");
        uint256 distributed = vm.parseJsonUint(json, ".distributed");
        uint256 rebate = vm.parseJsonUint(json, ".rebate");

        // Fund FeeDistributor with stETH shares if needed
        uint256 pending = feeDistributor.pendingSharesToDistribute();
        if (pending < distributed + rebate) {
            uint256 needed = distributed + rebate - pending + 1 ether;
            _setBalance(address(feeDistributor), needed + 1 ether);
            vm.startBroadcast(address(feeDistributor));
            lido.submit{ value: needed }(address(0));
            vm.stopBroadcast();
        }

        // Warp to next valid consensus frame
        _waitForNextRefSlot();
        (uint256 refSlot, ) = hashConsensus.getCurrentFrame();

        // Build ReportData with mock strikes values
        IFeeOracle.ReportData memory data = IFeeOracle.ReportData({
            consensusVersion: oracle.getConsensusVersion(),
            refSlot: refSlot,
            treeRoot: root,
            treeCid: treeCid,
            logCid: logCid,
            distributed: distributed,
            rebate: rebate,
            strikesTreeRoot: keccak256(abi.encode("mock-strikes", refSlot)),
            strikesTreeCid: string.concat("mock-strikes-", vm.toString(refSlot))
        });

        // Reach consensus from all fast-lane members
        bytes32 reportHash = keccak256(abi.encode(data));
        uint256 cv = oracle.getConsensusVersion();
        (address[] memory members, ) = hashConsensus.getFastLaneMembers();
        for (uint256 i; i < members.length; ++i) {
            _setBalance(members[i]);
            vm.startBroadcast(members[i]);
            hashConsensus.submitReport(refSlot, reportHash, cv);
            vm.stopBroadcast();
        }

        // Submit report data
        vm.startBroadcast(members[0]);
        oracle.submitReportData(data, oracle.getContractVersion());
        vm.stopBroadcast();

        console.log("treeRoot", vm.toString(feeDistributor.treeRoot()));
        console.log("treeCid", feeDistributor.treeCid());
        console.log("logCid", feeDistributor.logCid());
    }

    function _waitForNextRefSlot() internal {
        (uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime) = hashConsensus.getChainConfig();
        (uint256 initialEpoch, uint256 epochsPerFrame, ) = hashConsensus.getFrameConfig();
        uint256 epoch = (block.timestamp - genesisTime) / secondsPerSlot / slotsPerEpoch;
        if (epoch < initialEpoch) {
            _warp(genesisTime + 1 + initialEpoch * slotsPerEpoch * secondsPerSlot);
        }
        (uint256 refSlot, ) = hashConsensus.getCurrentFrame();
        uint256 frameStart = genesisTime + (refSlot + slotsPerEpoch * epochsPerFrame + 1) * secondsPerSlot;
        if (frameStart > block.timestamp) _warp(frameStart);
    }
}
