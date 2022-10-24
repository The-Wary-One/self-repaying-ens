// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Script, stdJson, console2 } from "forge-std/Script.sol";
import { WETHGateway } from "alchemix/WETHGateway.sol";
import { Whitelist } from "alchemix/utils/Whitelist.sol";
import {
    SelfRepayingENS,
    IAlchemistV2,
    AlchemicTokenV2,
    ETHRegistrarController,
    BaseRegistrarImplementation,
    ICurveAlETHPool,
    ICurveCalc,
    IGelatoOps
} from "src/SelfRepayingENS.sol";

contract Toolbox is Script {

    using stdJson for string;

    // We must follow the alphabetical order of the json file.
    struct Config {
        IAlchemistV2 alchemist;
        ICurveAlETHPool alETHPool;
        ICurveCalc curveCalc;
        ETHRegistrarController controller;
        BaseRegistrarImplementation registrar;
        IGelatoOps gelatoOps;
        WETHGateway wethGateway;
        address gelato;
    }

    SelfRepayingENS private _srens;
    Config private _config;

    event log_named_address(string key, address val);

    /// @dev Check the last contract deployment on the target chain.
    function getLastSRENSDeployment() public returns (SelfRepayingENS) {
        // Try to get the cached value.
        if (address(_srens) != address(0)) {
            return _srens;
        }
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

        // Cache value.
        _srens = srens;
        return srens;
    }

    /// @dev Get the environment config.
    function getConfig() public returns (Config memory) {
        // Try to get the cached value.
        if (address(_config.alchemist) != address(0)) {
            return _config;
        }

        // Get the deployed contracts addresses from the json config file.
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/externals.json");
        string memory json = vm.readFile(path);
        // Will panic if the network config is missing.
        bytes memory raw = json.parseRaw(string.concat("$.chainId.", vm.toString(block.chainid)));
        Config memory config = abi.decode(raw, (Config));
        // Cache value.
        _config = config;
        return config;
    }

    /// @dev Check if the last deployed `SRENS` contract is ready to be used.
    function check() public returns (bool isReady, string memory message) {
        // Get the last deployment address on this chain.
        SelfRepayingENS srens = getLastSRENSDeployment();
        return check(srens);
    }

    /// @dev Check if a `SRENS` contract is ready to be used.
    function check(SelfRepayingENS srens) public returns (bool isReady, string memory message) {
        // Check if `srens` was deployed.
        if (address(srens).code.length == 0) {
            return (false, "Not Deployed");
        }

        // Get the chain config.
        Config memory config = getConfig();
        // Check if `srens` is whitelisted by Alchemix's AlchemistV2 alETH contract.
        Whitelist whitelist = Whitelist(config.alchemist.whitelist());
        if (!whitelist.isWhitelisted(address(srens))) {
            return (false, "Alchemix must whitelist the contract");
        }

        // All checks passed.
        return (true, "Contract ready !");
    }

    /// @dev Subscribe to renew `name`.
    function subscribe(string calldata name) external {
        // Check srens was deployed.
        (bool isReady, string memory message) = check();
        if (!isReady) {
            revert(message);
        }

        // Subscribe to renew `name`.
        SelfRepayingENS srens = getLastSRENSDeployment();
        vm.broadcast();
        srens.subscribe(name);
    }

    /// @dev Approve the last deployed srens contract to mint alETH debt.
    function approveMint() external {
        // Get the config.
        Config memory config = getConfig();
        // Get the last deployment address on this chain.
        SelfRepayingENS srens = getLastSRENSDeployment();

        // Approve srens to mint debt.
        vm.broadcast();
        config.alchemist.approveMint(address(srens), type(uint256).max);
    }

    /// @dev Create an Alchemix account.
    function depositUnderlying() external {
        // Get the config.
        Config memory config = getConfig();

        // Get the first supported yield ETH token.
        address[] memory supportedTokens = config.alchemist.getSupportedYieldTokens();
        // Create an Alchemix account.
        vm.broadcast();
        config.wethGateway.depositUnderlying{value: 10 ether}(
            address(config.alchemist),
            supportedTokens[0],
            10 ether,
            msg.sender,
            1
        );
    }

    /// @dev Commit to register a ENS name on the local chain.
    function commitName(string calldata name) external {
        // Get the config.
        Config memory config = getConfig();

        // Generate commitment.
        bytes32 commitment = config.controller.makeCommitment(
            name,
            msg.sender,
            keccak256(abi.encodePacked(name, msg.sender))
        );

        // Commit the commitment to commit to register the name. We love to commit even if our ex doesn't agree.
        vm.broadcast();
        config.controller.commit(commitment);

        // Now we must wait at least 1 min.
    }

    /// @dev Register a ENS name on the local chain.
    function registerName(string calldata name) external {
        // Get the config.
        Config memory config = getConfig();

        // Register name for 1 year.
        vm.broadcast();
        config.controller.register{value: 0.1 ether}(
            name,
            msg.sender,
            365 days,
            keccak256(abi.encodePacked(name, msg.sender))
        );
    }
}
