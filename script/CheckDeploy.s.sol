// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Script, stdJson, console2 } from "forge-std/Script.sol";
import { Whitelist } from "alchemix/utils/Whitelist.sol";
import {
    SelfRepayingENS
} from "src/SelfRepayingENS.sol";
import { GetConfig } from "script/GetConfig.s.sol";

contract CheckDeploy is Script {

    using stdJson for string;

    event log_named_address(string key, address val);

    /// @dev Check the last contract deployment on the target chain.
    function run() external returns (bool isReady, string memory message) {
        // Get the last deployment address on this chain.
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/broadcast/DeploySRENS.s.sol/",
            vm.toString(block.chainid),
            "/run-latest.json"
        );
        // Will throw if the file is missing.
        string memory json = vm.readFile(path);
        // Get the value at `contractAddress` of a `CREATE` transaction.
        address addr = json.readAddress(
            // FIXME: This should be correct "$.transactions.[?(@.transactionType == 'CREATE' && @.contractName == 'SelfRepayingENS')].contractAddress"
            "$.transactions[?(@.transactionType == 'CREATE')].contractAddress"
        );
        SelfRepayingENS srens = SelfRepayingENS(payable(addr));

        return check(srens);
    }

    /// @dev Check if the contract is ready to be used.
    function check(SelfRepayingENS srens) public returns (bool isReady, string memory message) {
        if (address(srens) == address(0)) {
            return (false, "Not Deployed");
        }
        emit log_named_address("Last contract deployed to", address(srens));

        GetConfig.Config memory config = (new GetConfig()).run();

        // Check if `srens` is whitelisted by Alchemix's AlchemistV2 alETH contract.
        Whitelist whitelist = Whitelist(config.alchemist.whitelist());
        if (!whitelist.isWhitelisted(address(srens))) {
            return (false, "Alchemix must whitelist the contract");
        }
        console2.logString("Contract whitelisted by Alchemix");

        return (true, "Contract ready !");
    }
}
