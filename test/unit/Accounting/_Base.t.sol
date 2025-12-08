// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { IBaseModule, NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";

import { Accounting } from "src/Accounting.sol";

import { Stub } from "../../helpers/mocks/Stub.sol";
import { LidoMock } from "../../helpers/mocks/LidoMock.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";
import { LidoLocatorMock } from "../../helpers/mocks/LidoLocatorMock.sol";
import { BurnerMock } from "../../helpers/mocks/BurnerMock.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { Fixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";
import { DistributorMock } from "../../helpers/mocks/DistributorMock.sol";

contract FailedReceiverStub {
    receive() external payable {
        revert("receive failed");
    }
}

contract AccountingFixtures is Test, Fixtures, Utilities, InvariantAsserts {
    LidoLocatorMock internal locator;
    WstETHMock internal wstETH;
    LidoMock internal stETH;

    Accounting public accounting;
    Stub public stakingModule;
    DistributorMock public feeDistributor;
    BurnerMock internal burner;

    address internal admin;
    address internal user;
    address internal stranger;
    address internal testChargePenaltyRecipient;

    uint256 internal nodeOperatorsCount;

    event AssertInvariants();

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        emit AssertInvariants();
        assertAccountingTotalBondShares(nodeOperatorsCount, stETH, accounting);
        assertAccountingBurnerApproval(
            stETH,
            address(accounting),
            address(burner)
        );
        assertAccountingUnusedStorageSlots(accounting);
        vm.resumeGasMetering();
    }

    function mock_getNodeOperatorsCount(uint256 returnValue) internal {
        vm.mockCall(
            address(stakingModule),
            abi.encodeWithSelector(
                IStakingModule.getNodeOperatorsCount.selector
            ),
            abi.encode(returnValue)
        );
        nodeOperatorsCount = returnValue;
    }

    function mock_getNodeOperatorNonWithdrawnKeys(
        uint256 returnValue
    ) internal {
        vm.mockCall(
            address(stakingModule),
            abi.encodeWithSelector(
                IBaseModule.getNodeOperatorNonWithdrawnKeys.selector,
                0
            ),
            abi.encode(returnValue)
        );
    }

    function mock_updateDepositableValidatorsCount() internal {
        vm.mockCall(
            address(stakingModule),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            ),
            ""
        );
    }

    function mock_getNodeOperatorOwner(address owner) internal {
        vm.mockCall(
            address(stakingModule),
            abi.encodeWithSelector(
                IBaseModule.getNodeOperatorOwner.selector,
                0
            ),
            abi.encode(owner)
        );
    }

    function mock_getNodeOperatorManagementProperties(
        address managerAddress,
        address rewardAddress,
        bool extendedManagerPermissions
    ) internal {
        vm.mockCall(
            address(stakingModule),
            abi.encodeWithSelector(
                IBaseModule.getNodeOperatorManagementProperties.selector,
                0
            ),
            abi.encode(
                NodeOperatorManagementProperties(
                    managerAddress,
                    rewardAddress,
                    extendedManagerPermissions
                )
            )
        );
    }

    function addBond(uint256 nodeOperatorId, uint256 amount) internal {
        vm.deal(address(stakingModule), amount);
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: amount }(user, nodeOperatorId);
    }

    function ethToSharesToEth(uint256 amount) internal view returns (uint256) {
        return stETH.getPooledEthByShares(stETH.getSharesByPooledEth(amount));
    }
}

contract BaseTest is AccountingFixtures {
    function setUp() public virtual {
        admin = nextAddress("ADMIN");

        user = nextAddress("USER");
        stranger = nextAddress("STRANGER");
        testChargePenaltyRecipient = nextAddress("CHARGERECIPIENT");

        (locator, wstETH, stETH, burner, ) = initLido();

        stakingModule = new Stub();
        mock_updateDepositableValidatorsCount();

        IBondCurve.BondCurveIntervalInput[]
            memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        feeDistributor = new DistributorMock(address(stETH));

        accounting = new Accounting(
            address(locator),
            address(stakingModule),
            address(feeDistributor),
            4 weeks,
            365 days
        );

        feeDistributor.setAccounting(address(accounting));

        _enableInitializers(address(accounting));

        accounting.initialize(
            curve,
            admin,
            8 weeks,
            testChargePenaltyRecipient
        );

        vm.startPrank(admin);

        accounting.grantRole(accounting.PAUSE_ROLE(), admin);
        accounting.grantRole(accounting.RESUME_ROLE(), admin);
        accounting.grantRole(accounting.MANAGE_BOND_CURVES_ROLE(), admin);
        accounting.grantRole(accounting.SET_BOND_CURVE_ROLE(), admin);
        vm.stopPrank();
    }

    function _operator(uint256 ongoing, uint256 withdrawn) internal virtual {
        mock_getNodeOperatorNonWithdrawnKeys(ongoing - withdrawn);
        mock_getNodeOperatorsCount(1);
    }

    function _deposit(uint256 bond) internal virtual {
        vm.deal(address(stakingModule), bond);
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: bond }({
            from: address(0),
            nodeOperatorId: 0
        });
    }
}

abstract contract BondAmountModifiersTest {
    // 1 key  -> 2 ether
    // 2 keys -> 4 ether
    // n keys -> 2 + (n - 1) * 2 ether
    function test_default() public virtual;

    // 1 key  -> 2 ether
    // 2 keys -> 3 ether
    // n keys -> 2 + (n - 1) * 1 ether
    function test_WithCurve() public virtual;

    // 1 key  -> 2 ether + 1 ether
    // 2 keys -> 4 ether + 1 ether
    // n keys -> 2 + (n - 1) * 2 ether + 1 ether
    function test_WithLocked() public virtual;

    // 1 key  -> 2 ether + 1 ether
    // 2 keys -> 3 ether + 1 ether
    // n keys -> 2 + (n - 1) * 1 ether + 1 ether
    function test_WithCurveAndLocked() public virtual;
}

abstract contract BondStateBaseTest is BondAmountModifiersTest, BaseTest {
    IBondCurve.BondCurveIntervalInput[] public curveWithDiscount;
    IBondCurve.BondCurveIntervalInput[] public individualCurve;

    constructor() {
        curveWithDiscount.push(
            IBondCurve.BondCurveIntervalInput({
                minKeysCount: 1,
                trend: 2 ether
            })
        );
        curveWithDiscount.push(
            IBondCurve.BondCurveIntervalInput({
                minKeysCount: 2,
                trend: 1 ether
            })
        );
        individualCurve.push(
            IBondCurve.BondCurveIntervalInput({
                minKeysCount: 1,
                trend: 1.8 ether
            })
        );
        individualCurve.push(
            IBondCurve.BondCurveIntervalInput({
                minKeysCount: 2,
                trend: 0.9 ether
            })
        );
    }

    function setUp() public virtual override {
        super.setUp();
        mock_getNodeOperatorManagementProperties(user, user, false);
    }

    function _curve(
        IBondCurve.BondCurveIntervalInput[] memory curve
    ) internal virtual {
        vm.startPrank(admin);
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(0, curveId);
        vm.stopPrank();
    }

    function _lock(uint256 amount) internal virtual {
        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, amount);
    }

    function test_WithOneWithdrawnValidator() public virtual;

    function test_WithBond() public virtual;

    function test_WithBondAndOneWithdrawnValidator() public virtual;

    function test_WithExcessBond() public virtual;

    function test_WithExcessBondAndOneWithdrawnValidator() public virtual;

    function test_WithMissingBond() public virtual;

    function test_WithMissingBondAndOneWithdrawnValidator() public virtual;
}

abstract contract GetRequiredBondBaseTest is BondStateBaseTest {
    function test_OneWithdrawnOneAddedValidator() public virtual;

    function test_WithBondAndOneWithdrawnAndOneAddedValidator() public virtual;

    function test_WithExcessBondAndOneWithdrawnAndOneAddedValidator()
        public
        virtual;

    function test_WithMissingBondAndOneWithdrawnAndOneAddedValidator()
        public
        virtual;
}

abstract contract GetRequiredBondForKeysBaseTest is BaseTest {
    function _curve(
        IBondCurve.BondCurveIntervalInput[] memory curve
    ) internal virtual {
        vm.startPrank(admin);
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(0, curveId);
        vm.stopPrank();
    }

    function test_default() public virtual;

    function test_WithCurve() public virtual;
}

abstract contract RewardsBaseTest is BondStateBaseTest {
    struct RewardsLeaf {
        bytes32[] proof;
        uint256 nodeOperatorId;
        uint256 shares;
    }

    RewardsLeaf leaf;

    uint256 sharesAsFee;
    uint256 stETHAsFee;
    uint256 wstETHAsFee;
    uint256 unstETHAsFee;
    uint256 unstETHSharesAsFee;

    address internal rewardAddress;
    address internal rewardsClaimer;

    function setUp() public override {
        super.setUp();
        rewardAddress = nextAddress("reward address");
        rewardsClaimer = nextAddress("rewards claimer");
        mock_getNodeOperatorManagementProperties(user, rewardAddress, false);
    }

    function _rewards(uint256 fee) internal {
        vm.deal(address(feeDistributor), fee);
        vm.prank(address(feeDistributor));
        sharesAsFee = stETH.submit{ value: fee }(address(0));
        stETHAsFee = stETH.getPooledEthByShares(sharesAsFee);
        wstETHAsFee = wstETH.getWstETHByStETH(stETHAsFee);
        unstETHAsFee = stETH.getPooledEthByShares(sharesAsFee);
        unstETHSharesAsFee = stETH.getSharesByPooledEth(unstETHAsFee);
        leaf = RewardsLeaf({
            proof: new bytes32[](1),
            nodeOperatorId: 0,
            shares: sharesAsFee
        });
    }
}

abstract contract ClaimRewardsBaseTest is RewardsBaseTest {
    function test_WithDesirableValue() public virtual;

    function test_WithZeroValue() public virtual;

    function test_ExcessBondWithoutProof() public virtual;

    function test_SenderIsRewardAddress() public virtual;

    function test_SenderIsRewardsClaimer() public virtual;

    function test_RevertWhen_SenderIsNotEligible() public virtual;

    function test_RevertWhen_NodeOperatorDoesNotExist() public virtual;
}

contract BaseConstructorTest is AccountingFixtures {
    function setUp() public virtual {
        admin = nextAddress("ADMIN");

        user = nextAddress("USER");
        stranger = nextAddress("STRANGER");
        testChargePenaltyRecipient = nextAddress("CHARGERECIPIENT");

        (locator, wstETH, stETH, , ) = initLido();

        stakingModule = new Stub();
        feeDistributor = new DistributorMock(address(stETH));
    }
}

contract BaseInitTest is AccountingFixtures {
    function setUp() public virtual {
        admin = nextAddress("ADMIN");

        user = nextAddress("USER");
        stranger = nextAddress("STRANGER");
        testChargePenaltyRecipient = nextAddress("CHARGERECIPIENT");

        (locator, wstETH, stETH, burner, ) = initLido();

        stakingModule = new Stub();
        feeDistributor = new DistributorMock(address(stETH));

        accounting = new Accounting(
            address(locator),
            address(stakingModule),
            address(feeDistributor),
            4 weeks,
            365 days
        );

        feeDistributor.setAccounting(address(accounting));
    }
}
