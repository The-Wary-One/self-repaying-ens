// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {TestBase} from "../TestBase.sol";

contract BugScenarioTests is TestBase {
    /// @dev Test the bug in v1.0.0 where `srens` tries to create a gelato tasks every time `subscriber`'s names to renew array is empty.
    function testFork_subscribe_whenNamesToRenewArrayIsEmpty() external {
        // Act as scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);

        // Scoopy, the subscriber, needs to allow `srens` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(srens), type(uint256).max);

        // Subscribe to the Self Repaying ENS service for `name`.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(scoopy, name, name);
        srens.subscribe(name);

        // Unsubscribe from the Self Repaying ENS service for `name`.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Unsubscribe(scoopy, name, name);
        srens.unsubscribe(name);

        // Subscribe to the Self Repaying ENS service for `alchemix`. The order is important.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(scoopy, "alchemix", "alchemix");
        srens.subscribe("alchemix");
    }
}
