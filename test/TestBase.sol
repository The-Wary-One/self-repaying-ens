// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "../lib/forge-std/src/Test.sol";

import {WETHGateway} from "../lib/alchemix/src/WETHGateway.sol";
import {Whitelist} from "../lib/alchemix/src/utils/Whitelist.sol";

import {Toolbox, ToolboxLocal} from "../script/ToolboxLocal.s.sol";

import {LibDataTypes, SelfRepayingENS} from "../src/SelfRepayingENS.sol";

contract TestBase is Test {
    /* --- TEST CONFIG --- */
    ToolboxLocal toolbox;
    Toolbox.Config config;
    SelfRepayingENS srens;
    address scoopy = address(0xbadbabe);
    string name = "SelfRepayingENS";
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 constant gelatoFee = 0.001 ether;

    /// @dev Copied from the `SelfRepayingENS` contract.
    event Subscribe(address indexed subscriber, string indexed indexedName, string name);
    event Unsubscribe(address indexed subscriber, string indexed indexedName, string name);
    /// @dev ENS `ETHRegistrarController` contract event
    event NameRenewed(string name, bytes32 indexed label, uint256 cost, uint256 expires);

    /// @dev Setup the environment for the tests.
    function setUp() public virtual {
        // Make sure we run the tests on a mainnet fork.
        Chain memory mainnet = getChain("mainnet");
        uint256 BLOCK_NUMBER_MAINNET = vm.envUint("BLOCK_NUMBER_MAINNET");
        vm.createSelectFork(mainnet.rpcUrl, BLOCK_NUMBER_MAINNET);
        require(block.chainid == 1, "Tests should be run on a mainnet fork");

        toolbox = new ToolboxLocal();
        // Deploy the SelfRepayingENS contract.
        srens = toolbox.deployTestSRENS();
        // Get the mainnet config.
        config = toolbox.getConfig();

        // The contract is ready to be used.
        // Add it to the alchemist whitelist.
        Whitelist whitelist = Whitelist(config.alchemist.whitelist());
        vm.prank(whitelist.owner());
        whitelist.add(address(srens));
        require(whitelist.isWhitelisted(address(srens)));
        (bool isReady,) = toolbox.check(srens);
        require(isReady);

        // Give 100 ETH to Scoopy Trooples even if he doesn't need it 🙂.
        vm.label(scoopy, "scoopy");
        vm.deal(scoopy, 100 ether);

        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Get the first supported yield ETH token.
        address[] memory supportedTokens = config.alchemist.getSupportedYieldTokens();
        // Create an Alchemix account.
        config.wethGateway.depositUnderlying{value: 10 ether}(
            address(config.alchemist), supportedTokens[0], 10 ether, scoopy, 1
        );

        // Check `name`'s rent price.
        uint256 registrationDuration = config.controller.MIN_REGISTRATION_DURATION();
        uint256 namePrice = config.controller.rentPrice(name, registrationDuration);

        // Register `name`.
        // To register a ENS name we must first send a commitment, wait some time then register it.
        // Get the commitment.
        bytes32 secret = keccak256(bytes("SuperSecret"));
        bytes32 commitment = config.controller.makeCommitment(name, scoopy, secret);
        // Submit the commitment to the `ETHRegistrarController`.
        config.controller.commit(commitment);
        // Wait the waiting period.
        vm.warp(block.timestamp + config.controller.minCommitmentAge());
        // Register `name` for `namePrice` and `registrationDuration`.
        // ENS recommend sending at least a 5% premium to cover the price fluctuations. They send the leftover ETH back.
        uint256 namePriceWithPremium = namePrice * 105 / 100;
        config.controller.register{value: namePriceWithPremium}(name, scoopy, registrationDuration, secret);

        vm.stopPrank();
    }

    /// @dev Simulate a Gelato Ops call with fees.
    function execRenewTask(uint256 fee, string memory _name, address subscriber) internal {
        LibDataTypes.ModuleData memory moduleData = toolbox.getModuleData(srens, subscriber);

        // Act as the Gelato main contract.
        vm.prank(config.gelato);

        // Execute the renew Gelato Task for `fee`.
        config.gelatoOps.exec(
            address(srens),
            address(srens),
            abi.encodeCall(srens.renew, (_name, subscriber)),
            moduleData,
            fee,
            ETH,
            false,
            true
        );
    }
}
