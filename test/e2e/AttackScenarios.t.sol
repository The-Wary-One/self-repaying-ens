// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "../TestBase.sol";
import {Freeloader} from "./Freeloader.sol";

import {LibDataTypes} from "../../src/SelfRepayingENS.sol";

contract AttackScenarioTests is TestBase {
    /// @dev Test another contract cannot renew their name using one of `srens` user funds.
    /// @dev The `SelfRepayingENS` contract had this vunerability. See commit `413f626002954a0e70723b25448a24977f039eb7`.
    function testFork_freeloaderAttack() external {
        // Act as scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);
        // Scoopy, the subscriber, needs to allow `srens` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(srens), type(uint256).max);
        // Subscribe to the Self Repaying ENS service for `name`.
        srens.subscribe(name);
        vm.stopPrank();

        // Setup the attacker account and contract.
        address techno = address(0xbadbad);
        vm.label(techno, "techno");
        vm.deal(techno, 1 ether);
        // Act as techno, an EOA.
        vm.startPrank(techno, techno);
        // Other name to renew.
        string memory otherName = "FreeloaderENS";
        // Check `otherName`'s rent price.
        uint256 registrationDuration = config.controller.MIN_REGISTRATION_DURATION();
        uint256 namePrice = config.controller.rentPrice(otherName, registrationDuration);
        // Register `otherName`.
        bytes32 secret = keccak256(bytes("SuperSecret"));
        bytes32 commitment = config.controller.makeCommitment(otherName, techno, secret);
        config.controller.commit(commitment);
        vm.warp(block.timestamp + config.controller.minCommitmentAge());
        config.controller.register{value: namePrice}(otherName, techno, registrationDuration, secret);
        // Warp to some time after `otherName` expiry date.
        bytes32 labelHash = keccak256(bytes(otherName));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt + 1 days);

        // Deploy the Freeloader contract to use `scoopy`'s account to renew `otherName`.
        Freeloader freeloader = new Freeloader(
            srens,
            config.gelatoOps
        );

        freeloader.subscribe(otherName, scoopy);
        vm.stopPrank();

        // Gelato now execute the defined task.
        // `srens` called by Gelato should not renew `otherName` by minting some alETH debt using `scoopy` account.
        LibDataTypes.ModuleData memory moduleData = freeloader._getModuleData(scoopy, otherName);
        vm.prank(config.gelato);
        // It should not be possible !
        vm.expectRevert("Ops.exec: NoErrorSelector");
        config.gelatoOps.exec(
            address(freeloader),
            address(srens),
            abi.encodeCall(srens.renew, (otherName, scoopy)),
            moduleData,
            gelatoFee,
            ETH,
            false,
            true
        );
    }
}
