// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperator, NodeOperatorManagementProperties } from "../../../../src/interfaces/IBaseModule.sol";
import { IAccounting } from "../../../../src/interfaces/IAccounting.sol";
import { IBondCurve } from "../../../../src/interfaces/IBondCurve.sol";
import { ILido } from "../../../../src/interfaces/ILido.sol";
import { IMerkleGate } from "../../../../src/interfaces/IMerkleGate.sol";
import { IVettedGate } from "../../../../src/interfaces/IVettedGate.sol";
import { PermitHelper } from "../../../helpers/Permit.sol";
import { MerkleTree } from "../../../helpers/MerkleTree.sol";
import { CSMIntegrationBase } from "../common/ModuleTypeBase.sol";

contract IntegrationTestBase is PermitHelper, CSMIntegrationBase {
    address internal user;
    address internal nodeOperator;
    address internal anotherNodeOperator;
    address internal stranger;
    uint256 internal userPrivateKey;
    uint256 internal strangerPrivateKey;
    MerkleTree internal merkleTree;
    string internal cid;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        assertModuleEnqueuedCount(module);
        assertModuleUnusedStorageSlots(module);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(
            lido,
            address(accounting),
            locator.burner()
        );
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public virtual {
        _setUpModule();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        vm.startPrank(vettedGate.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        vettedGate.grantRole(vettedGate.SET_TREE_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        userPrivateKey = 0xa11ce;
        user = vm.addr(userPrivateKey);
        strangerPrivateKey = 0x517a4637;
        stranger = vm.addr(strangerPrivateKey);
        nodeOperator = nextAddress("NodeOperator");
        anotherNodeOperator = nextAddress("AnotherNodeOperator");

        merkleTree = new MerkleTree();
        merkleTree.pushLeaf(abi.encode(nodeOperator));
        merkleTree.pushLeaf(abi.encode(anotherNodeOperator));
        merkleTree.pushLeaf(abi.encode(stranger));

        cid = "someOtherCid";

        vettedGate.setTreeParams(merkleTree.root(), cid);
    }
}

contract PermissionlessCreateNodeOperatorTest is IntegrationTestBase {
    uint256 internal immutable KEYS_COUNT;

    constructor() {
        KEYS_COUNT = 1;
    }

    function test_createNodeOperatorETH() public assertInvariants {
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            KEYS_COUNT
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            KEYS_COUNT,
            permissionlessGate.CURVE_ID()
        );
        vm.deal(nodeOperator, amount);

        uint256 preTotalShares = accounting.totalBondShares();

        uint256 shares = lido.getSharesByPooledEth(amount);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("PermissionlessGate.addNodeOperatorETH");
        uint256 noId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });
        vm.stopSnapshotGas();

        assertEq(
            accounting.getBondCurveId(noId),
            permissionlessGate.CURVE_ID()
        );
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_createNodeOperatorStETH() public assertInvariants {
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, 32 ether);
        lido.submit{ value: 32 ether }(address(0));

        uint256 preTotalShares = accounting.totalBondShares();

        lido.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(
            KEYS_COUNT
        );
        uint256 shares = lido.getSharesByPooledEth(
            accounting.getBondAmountByKeysCount(
                KEYS_COUNT,
                permissionlessGate.CURVE_ID()
            )
        );

        vm.startSnapshotGas("PermissionlessGate.addNodeOperatorStETH");
        uint256 noId = permissionlessGate.addNodeOperatorStETH({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            referrer: address(0)
        });
        vm.stopSnapshotGas();

        assertEq(
            accounting.getBondCurveId(noId),
            permissionlessGate.CURVE_ID()
        );
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_createNodeOperatorWstETH() public assertInvariants {
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, 32 ether);
        lido.submit{ value: 32 ether }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 preTotalShares = accounting.totalBondShares();

        wstETH.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(
            KEYS_COUNT
        );
        uint256 wstETHAmount = wstETH.wrap(
            accounting.getBondAmountByKeysCount(
                KEYS_COUNT,
                permissionlessGate.CURVE_ID()
            )
        );

        uint256 shares = lido.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );

        vm.startSnapshotGas("PermissionlessGate.addNodeOperatorWstETH");
        uint256 noId = permissionlessGate.addNodeOperatorWstETH({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            referrer: address(0)
        });
        vm.stopSnapshotGas();

        assertEq(
            accounting.getBondCurveId(noId),
            permissionlessGate.CURVE_ID()
        );
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }
}

contract PermissionlessCreateNodeOperator10KeysTest is
    PermissionlessCreateNodeOperatorTest
{
    constructor() {
        KEYS_COUNT = 10;
    }
}

contract VettedGateCreateNodeOperatorTest is IntegrationTestBase {
    uint256 internal immutable keysCount;

    constructor() {
        keysCount = 1;
    }

    function test_createNodeOperatorETH() public assertInvariants {
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            keysCount,
            vettedGate.curveId()
        );
        vm.deal(nodeOperator, amount);

        uint256 preTotalShares = accounting.totalBondShares();

        uint256 shares = lido.getSharesByPooledEth(amount);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("VettedGate.addNodeOperatorETH");
        uint256 noId = vettedGate.addNodeOperatorETH{ value: amount }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: merkleTree.getProof(0),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(accounting.getBondCurveId(noId), vettedGate.curveId());
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
        assertTrue(vettedGate.isConsumed(nodeOperator));
    }

    function test_createNodeOperatorETH_revertWhen_InvalidProof()
        public
        assertInvariants
    {
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            keysCount,
            vettedGate.curveId()
        );
        vm.deal(nodeOperator, amount);

        uint256 preTotalShares = accounting.totalBondShares();

        bytes32[] memory proof = merkleTree.getProof(1);

        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        vm.prank(nodeOperator);
        vettedGate.addNodeOperatorETH{ value: amount }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: proof,
            referrer: address(0)
        });

        assertEq(accounting.totalBondShares(), preTotalShares);
        assertFalse(vettedGate.isConsumed(nodeOperator));
    }

    function test_createNodeOperatorStETH() public assertInvariants {
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, 32 ether);
        lido.submit{ value: 32 ether }(address(0));

        uint256 preTotalShares = accounting.totalBondShares();

        lido.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );

        uint256 shares = lido.getSharesByPooledEth(
            accounting.getBondAmountByKeysCount(keysCount, vettedGate.curveId())
        );
        vm.startSnapshotGas("VettedGate.addNodeOperatorStETH");
        uint256 noId = vettedGate.addNodeOperatorStETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            proof: merkleTree.getProof(0),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(accounting.getBondCurveId(noId), vettedGate.curveId());
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
        assertTrue(vettedGate.isConsumed(nodeOperator));
    }

    function test_createNodeOperatorStETH_revertWhen_InvalidProof()
        public
        assertInvariants
    {
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, 32 ether);
        lido.submit{ value: 32 ether }(address(0));

        uint256 preTotalShares = accounting.totalBondShares();

        lido.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );

        bytes32[] memory proof = merkleTree.getProof(1);

        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        vettedGate.addNodeOperatorStETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            proof: proof,
            referrer: address(0)
        });
        vm.stopPrank();

        assertEq(accounting.totalBondShares(), preTotalShares);
        assertFalse(vettedGate.isConsumed(nodeOperator));
    }

    function test_createNodeOperatorWstETH() public assertInvariants {
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, 32 ether);
        lido.submit{ value: 32 ether }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 preTotalShares = accounting.totalBondShares();
        wstETH.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 wstETHAmount = wstETH.wrap(
            accounting.getBondAmountByKeysCount(keysCount, vettedGate.curveId())
        );

        uint256 shares = lido.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );

        vm.startSnapshotGas("VettedGate.addNodeOperatorWstETH");
        uint256 noId = vettedGate.addNodeOperatorWstETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            proof: merkleTree.getProof(0),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(accounting.getBondCurveId(noId), vettedGate.curveId());
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
        assertTrue(vettedGate.isConsumed(nodeOperator));
    }

    function test_createNodeOperatorWstETH_revertWhen_InvalidProof()
        public
        assertInvariants
    {
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, 32 ether);
        lido.submit{ value: 32 ether }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 preTotalShares = accounting.totalBondShares();
        wstETH.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );

        bytes32[] memory proof = merkleTree.getProof(1);

        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        vettedGate.addNodeOperatorWstETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            proof: proof,
            referrer: address(0)
        });
        vm.stopPrank();

        assertEq(accounting.totalBondShares(), preTotalShares);
        assertFalse(vettedGate.isConsumed(nodeOperator));
    }
}

contract VettedGateCreateNodeOperator10KeysTest is
    VettedGateCreateNodeOperatorTest
{
    constructor() {
        keysCount = 10;
    }
}

contract VettedGateMiscTest is IntegrationTestBase {
    uint256 internal constant KEYS_COUNT = 2;

    function test_claimBondCurve() public assertInvariants {
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            KEYS_COUNT
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            KEYS_COUNT,
            permissionlessGate.CURVE_ID()
        );
        vm.deal(nodeOperator, amount);

        vm.prank(nodeOperator);
        uint256 noId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        assertEq(
            accounting.getBondCurveId(noId),
            permissionlessGate.CURVE_ID()
        );
        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("VettedGate.claimBondCurve");
        vettedGate.claimBondCurve(noId, merkleTree.getProof(0));
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(accounting.getBondCurveId(noId), vettedGate.curveId());
        assertTrue(accounting.getClaimableBondShares(noId) > 0);
        assertTrue(vettedGate.isConsumed(nodeOperator));
    }

    function test_claimBondCurve_revertWhenInvalidProof()
        public
        assertInvariants
    {
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            KEYS_COUNT
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            KEYS_COUNT,
            permissionlessGate.CURVE_ID()
        );
        vm.deal(nodeOperator, amount);

        vm.prank(nodeOperator);
        uint256 noId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        assertEq(
            accounting.getBondCurveId(noId),
            permissionlessGate.CURVE_ID()
        );

        bytes32[] memory proof = merkleTree.getProof(1);

        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        vm.startPrank(nodeOperator);
        vettedGate.claimBondCurve(noId, proof);
        vm.stopPrank();

        assertEq(
            accounting.getBondCurveId(noId),
            accounting.DEFAULT_BOND_CURVE_ID()
        );
        assertEq(accounting.getClaimableBondShares(noId), 0);
        assertFalse(vettedGate.isConsumed(nodeOperator));
    }

    function test_setTreeParams() public {
        merkleTree = new MerkleTree();
        merkleTree.pushLeaf(abi.encode(stranger));
        merkleTree.pushLeaf(abi.encode(nodeOperator));
        merkleTree.pushLeaf(abi.encode(anotherNodeOperator));

        cid = "yetAnotherOtherCid";

        vettedGate.setTreeParams(merkleTree.root(), cid);

        assertEq(vettedGate.treeRoot(), merkleTree.root());
        assertEq(vettedGate.treeCid(), cid);
    }

    function test_referralSeason() public assertInvariants {
        // Create a new node operator
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            KEYS_COUNT
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            KEYS_COUNT,
            vettedGate.curveId()
        );
        vm.deal(nodeOperator, amount);

        uint256 shares = lido.getSharesByPooledEth(amount);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("VettedGate.addNodeOperatorETH");
        uint256 firstNoId = vettedGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: merkleTree.getProof(0),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        // Start a new referral season
        IBondCurve.BondCurveIntervalInput[]
            memory referralBondCurve = new IBondCurve.BondCurveIntervalInput[](
                2
            );
        referralBondCurve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 1.2 ether
        });
        referralBondCurve[1] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 2,
            trend: 1 ether
        });

        vm.startPrank(
            accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0)
        );
        accounting.grantRole(
            accounting.MANAGE_BOND_CURVES_ROLE(),
            address(this)
        );
        vm.stopPrank();

        uint256 referralBondCurveId = accounting.addBondCurve(
            referralBondCurve
        );

        vm.startPrank(
            vettedGate.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0)
        );
        vettedGate.grantRole(
            vettedGate.START_REFERRAL_SEASON_ROLE(),
            address(this)
        );
        vm.stopPrank();

        vettedGate.startNewReferralProgramSeason(referralBondCurveId, 1);

        // Create a new node operator with a referrer pointing to the first one
        (keys, signatures) = keysSignatures(KEYS_COUNT);
        amount = accounting.getBondAmountByKeysCount(
            KEYS_COUNT,
            vettedGate.curveId()
        );
        vm.deal(anotherNodeOperator, amount);

        shares = lido.getSharesByPooledEth(amount);

        vm.startPrank(anotherNodeOperator);
        vm.startSnapshotGas("VettedGate.addNodeOperatorETH");
        vettedGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: merkleTree.getProof(1),
            referrer: nodeOperator
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(vettedGate.getReferralsCount(nodeOperator), 1);

        // Claim the referral bond curve
        bytes32[] memory proof = merkleTree.getProof(0);

        vm.prank(nodeOperator);
        vm.startSnapshotGas("VettedGate.claimReferrerBondCurve");
        vettedGate.claimReferrerBondCurve(firstNoId, proof);
        vm.stopSnapshotGas();

        assertEq(accounting.getBondCurveId(firstNoId), referralBondCurveId);
        assertTrue(accounting.getClaimableBondShares(firstNoId) > 0);
        assertTrue(vettedGate.isReferrerConsumed(nodeOperator));

        // Attempt to claim the referral bond curve again
        vm.expectRevert(IMerkleGate.AlreadyConsumed.selector);
        vm.prank(nodeOperator);
        vettedGate.claimReferrerBondCurve(firstNoId, proof);
    }

    function test_referralSeason_noClaimsAfterEnd() public assertInvariants {
        // Create a new node operator
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            KEYS_COUNT
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            KEYS_COUNT,
            vettedGate.curveId()
        );
        vm.deal(nodeOperator, amount);

        uint256 shares = lido.getSharesByPooledEth(amount);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("VettedGate.addNodeOperatorETH");
        uint256 firstNoId = vettedGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: merkleTree.getProof(0),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        // Start a new referral season
        IBondCurve.BondCurveIntervalInput[]
            memory referralBondCurve = new IBondCurve.BondCurveIntervalInput[](
                2
            );
        referralBondCurve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 1.2 ether
        });
        referralBondCurve[1] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 2,
            trend: 1 ether
        });

        vm.startPrank(
            accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0)
        );
        accounting.grantRole(
            accounting.MANAGE_BOND_CURVES_ROLE(),
            address(this)
        );
        vm.stopPrank();

        uint256 referralBondCurveId = accounting.addBondCurve(
            referralBondCurve
        );

        vm.startPrank(
            vettedGate.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0)
        );
        vettedGate.grantRole(
            vettedGate.START_REFERRAL_SEASON_ROLE(),
            address(this)
        );
        vm.stopPrank();

        vettedGate.startNewReferralProgramSeason(referralBondCurveId, 1);

        // Create a new node operator with a referrer pointing to the first one
        (keys, signatures) = keysSignatures(KEYS_COUNT);
        amount = accounting.getBondAmountByKeysCount(
            KEYS_COUNT,
            vettedGate.curveId()
        );
        vm.deal(anotherNodeOperator, amount);

        shares = lido.getSharesByPooledEth(amount);

        vm.startPrank(anotherNodeOperator);
        vm.startSnapshotGas("VettedGate.addNodeOperatorETH");
        vettedGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: merkleTree.getProof(1),
            referrer: nodeOperator
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(vettedGate.getReferralsCount(nodeOperator), 1);

        // End the referral season
        vm.startPrank(
            vettedGate.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0)
        );
        vettedGate.grantRole(
            vettedGate.END_REFERRAL_SEASON_ROLE(),
            address(this)
        );
        vm.stopPrank();

        vettedGate.endCurrentReferralProgramSeason();

        // Attempt to claim the referral bond curve
        bytes32[] memory proof = merkleTree.getProof(0);

        vm.expectRevert(IVettedGate.ReferralProgramIsNotActive.selector);
        vm.prank(nodeOperator);
        vettedGate.claimReferrerBondCurve(firstNoId, proof);
    }
}
