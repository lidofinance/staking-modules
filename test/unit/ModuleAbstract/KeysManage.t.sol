// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule, NodeOperator } from "src/interfaces/IBaseModule.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleVetKeys is ModuleFixtures {
    function test_vetKeys_OnUploadKeys() public assertInvariants {
        uint256 noId = createNodeOperator(2);

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(noId, 3);
        uploadMoreKeys(noId, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 3);
    }

    function test_vetKeys_Counters() public assertInvariants {
        uint256 noId = createNodeOperator(false);
        uint256 nonce = module.getNonce();
        uploadMoreKeys(noId, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 1);
        assertEq(no.depositableValidatorsCount, 1);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_vetKeys_VettedBackViaRemoveKey() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 7);
        unvetKeys({ noId: noId, to: 4 });
        no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 4);

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(noId, 5); // 7 - 2 removed at the next step.

        vm.prank(nodeOperator);
        module.removeKeys(noId, 4, 2); // Remove keys 4 and 5.

        no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 5);
    }
}

abstract contract ModuleDecreaseVettedSigningKeysCount is ModuleFixtures {
    function test_decreaseVettedSigningKeysCount_counters() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(noId, 1);
        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountDecreased(noId);
        unvetKeys({ noId: noId, to: 1 });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(module.getNonce(), nonce + 1);
        assertEq(no.totalVettedKeys, 1);
        assertEq(no.depositableValidatorsCount, 1);
    }

    function test_decreaseVettedSigningKeysCount_MultipleOperators() public assertInvariants {
        uint256 firstNoId = createNodeOperator(10);
        uint256 secondNoId = createNodeOperator(7);
        uint256 thirdNoId = createNodeOperator(15);
        uint256 newVettedFirst = 5;
        uint256 newVettedSecond = 3;

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(firstNoId, newVettedFirst);
        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountDecreased(firstNoId);

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(secondNoId, newVettedSecond);
        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountDecreased(secondNoId);

        module.decreaseVettedSigningKeysCount(
            _encodeNodeOperatorPair(firstNoId, secondNoId),
            bytes.concat(
                // Each vetted value mirrors the uint128 field used on-chain, so truncation is safe.
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes16(uint128(newVettedFirst)),
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes16(uint128(newVettedSecond))
            )
        );

        uint256 actualVettedFirst = module.getNodeOperator(firstNoId).totalVettedKeys;
        uint256 actualVettedSecond = module.getNodeOperator(secondNoId).totalVettedKeys;
        uint256 actualVettedThird = module.getNodeOperator(thirdNoId).totalVettedKeys;
        assertEq(actualVettedFirst, newVettedFirst);
        assertEq(actualVettedSecond, newVettedSecond);
        assertEq(actualVettedThird, 15);
    }

    function test_decreaseVettedSigningKeysCount_MultipleOperators_NoopOnEqualStaleValue() public assertInvariants {
        uint256 staleNoId = createNodeOperator(10);
        uint256 activeNoId = createNodeOperator(7);
        uint256 staleReportedVetted = 5;
        uint256 activeReportedVetted = 3;

        vm.prank(nodeOperator);
        module.removeKeys(staleNoId, staleReportedVetted, 5);
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(activeNoId, activeReportedVetted);
        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountDecreased(activeNoId);

        module.decreaseVettedSigningKeysCount(
            _encodeNodeOperatorPair(staleNoId, activeNoId),
            bytes.concat(
                // Each vetted value mirrors the uint128 field used on-chain, so truncation is safe.
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes16(uint128(staleReportedVetted)),
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes16(uint128(activeReportedVetted))
            )
        );

        assertEq(module.getNonce(), nonce + 1);
        assertEq(module.getNodeOperator(staleNoId).totalVettedKeys, staleReportedVetted);
        assertEq(module.getNodeOperator(activeNoId).totalVettedKeys, activeReportedVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_MissingVettedData() public {
        uint256 firstNoId = createNodeOperator(10);
        uint256 secondNoId = createNodeOperator(7);
        uint256 newVettedFirst = 5;

        vm.expectRevert();
        module.decreaseVettedSigningKeysCount(
            _encodeNodeOperatorPair(firstNoId, secondNoId),
            _encodeUint128Value(newVettedFirst)
        );
    }

    function test_decreaseVettedSigningKeysCount_NoopWhen_NewVettedEqOld() public {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 10;
        uint256 nonce = module.getNonce();

        unvetKeys(noId, newVetted);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(module.getNonce(), nonce);
        assertEq(no.totalVettedKeys, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedGreaterOld() public {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 15;

        vm.expectRevert(IBaseModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedLowerTotalDeposited() public {
        uint256 noId = createNodeOperator(10);
        module.obtainDepositData(5, "");
        uint256 newVetted = 4;

        vm.expectRevert(IBaseModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NodeOperatorDoesNotExist() public {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 15;

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        unvetKeys(noId + 1, newVetted);
    }
}

abstract contract ModuleGetSigningKeys is ModuleFixtures {
    function test_getSigningKeys() public assertInvariants brutalizeMemory {
        bytes memory keys = randomBytes(48 * 3);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: randomBytes(96 * 3)
        });

        bytes memory obtainedKeys = module.getSigningKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 3 });

        assertEq(obtainedKeys, keys, "unexpected keys");
    }

    function test_getSigningKeys_getNonExistingKeys() public assertInvariants brutalizeMemory {
        bytes memory keys = randomBytes(48);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: randomBytes(96)
        });

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 3 });
    }

    function test_getSigningKeys_getKeysFromOffset() public assertInvariants brutalizeMemory {
        bytes memory wantedKey = randomBytes(48);
        bytes memory keys = bytes.concat(randomBytes(48), wantedKey, randomBytes(48));

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: randomBytes(96 * 3)
        });

        bytes memory obtainedKeys = module.getSigningKeys({ nodeOperatorId: noId, startIndex: 1, keysCount: 1 });

        assertEq(obtainedKeys, wantedKey, "unexpected key at position 1");
    }

    function test_getSigningKeys_RevertWhen_InvalidOffset() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator(2);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeys({ nodeOperatorId: noId, startIndex: 2, keysCount: 1 });
    }

    function test_getSigningKeys_WhenNoNodeOperator() public assertInvariants brutalizeMemory {
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeys(0, 0, 1);
    }
}

abstract contract ModuleGetSigningKeysWithSignatures is ModuleFixtures {
    function test_getSigningKeysWithSignatures() public assertInvariants brutalizeMemory {
        bytes memory keys = randomBytes(48 * 3);
        bytes memory signatures = randomBytes(96 * 3);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: signatures
        });

        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module.getSigningKeysWithSignatures({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });

        assertEq(obtainedKeys, keys, "unexpected keys");
        assertEq(obtainedSignatures, signatures, "unexpected signatures");
    }

    function test_getSigningKeysWithSignatures_getNonExistingKeys() public assertInvariants brutalizeMemory {
        bytes memory keys = randomBytes(48);
        bytes memory signatures = randomBytes(96);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: signatures
        });

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeysWithSignatures({ nodeOperatorId: noId, startIndex: 0, keysCount: 3 });
    }

    function test_getSigningKeysWithSignatures_getKeysFromOffset() public assertInvariants brutalizeMemory {
        bytes memory wantedKey = randomBytes(48);
        bytes memory wantedSignature = randomBytes(96);
        bytes memory keys = bytes.concat(randomBytes(48), wantedKey, randomBytes(48));
        bytes memory signatures = bytes.concat(randomBytes(96), wantedSignature, randomBytes(96));

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: signatures
        });

        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module.getSigningKeysWithSignatures({
            nodeOperatorId: noId,
            startIndex: 1,
            keysCount: 1
        });

        assertEq(obtainedKeys, wantedKey, "unexpected key at position 1");
        assertEq(obtainedSignatures, wantedSignature, "unexpected sitnature at position 1");
    }

    function test_getSigningKeysWithSignatures_RevertWhen_InvalidOffset() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator(2);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeysWithSignatures({ nodeOperatorId: noId, startIndex: 2, keysCount: 1 });
    }

    function test_getSigningKeysWithSignatures_WhenNoNodeOperator() public assertInvariants brutalizeMemory {
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeysWithSignatures(0, 0, 1);
    }
}

abstract contract ModuleRemoveKeys is ModuleFixtures {
    bytes key0 = randomBytes(48);
    bytes key1 = randomBytes(48);
    bytes key2 = randomBytes(48);
    bytes key3 = randomBytes(48);
    bytes key4 = randomBytes(48);

    function test_singleKeyRemoval() public assertInvariants brutalizeMemory {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        // at the beginning
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key0);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 4);
        }
        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 1 });
        /*
            key4
            key1
            key2
            key3
        */

        // in between
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }
        module.removeKeys({ nodeOperatorId: noId, startIndex: 1, keysCount: 1 });
        /*
            key4
            key3
            key2
        */

        // at the end
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key2);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.removeKeys({ nodeOperatorId: noId, startIndex: 2, keysCount: 1 });
        /*
            key4
            key3
        */

        bytes memory obtainedKeys = module.getSigningKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 2 });
        assertEq(obtainedKeys, bytes.concat(key4, key3), "unexpected keys");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 2);
    }

    function test_multipleKeysRemovalFromStart() public assertInvariants brutalizeMemory {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key0);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 2 });

        bytes memory obtainedKeys = module.getSigningKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 3 });
        assertEq(obtainedKeys, bytes.concat(key3, key4, key2), "unexpected keys");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_multipleKeysRemovalInBetween() public assertInvariants brutalizeMemory {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key2);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({ nodeOperatorId: noId, startIndex: 1, keysCount: 2 });

        bytes memory obtainedKeys = module.getSigningKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 3 });
        assertEq(obtainedKeys, bytes.concat(key0, key3, key4), "unexpected keys");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_multipleKeysRemovalFromEnd() public assertInvariants brutalizeMemory {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key4);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key3);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({ nodeOperatorId: noId, startIndex: 3, keysCount: 2 });

        bytes memory obtainedKeys = module.getSigningKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 3 });
        assertEq(obtainedKeys, bytes.concat(key0, key1, key2), "unexpected keys");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_removeAllKeys() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: randomBytes(48 * 5),
            signatures: randomBytes(96 * 5)
        });

        {
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 0);
        }

        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 5 });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 0);
    }

    function test_removeKeys_nonceChanged() public assertInvariants {
        bytes memory keys = bytes.concat(key0);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: randomBytes(96)
        });

        uint256 nonce = module.getNonce();
        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 1 });
        assertEq(module.getNonce(), nonce + 1);
    }
}

abstract contract ModuleRemoveKeysReverts is ModuleFixtures {
    function test_removeKeys_RevertWhen_NoNodeOperator() public assertInvariants {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.removeKeys({ nodeOperatorId: 0, startIndex: 0, keysCount: 1 });
    }

    function test_removeKeys_RevertWhen_MoreThanAdded() public assertInvariants {
        uint256 noId = createNodeOperator({ managerAddress: address(this), keysCount: 1 });

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 2 });
    }

    function test_removeKeys_RevertWhen_LessThanDeposited() public assertInvariants {
        uint256 noId = createNodeOperator({ managerAddress: address(this), keysCount: 2 });

        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 1 });
    }

    function test_removeKeys_RevertWhen_NotEligible() public assertInvariants {
        uint256 noId = createNodeOperator({ managerAddress: address(this), keysCount: 1 });

        vm.prank(stranger);
        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 1 });
    }

    function test_removeKeys_RevertWhen_NoKeys() public assertInvariants {
        uint256 noId = createNodeOperator({ managerAddress: address(this), keysCount: 1 });

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.removeKeys({ nodeOperatorId: noId, startIndex: 0, keysCount: 0 });
    }
}
