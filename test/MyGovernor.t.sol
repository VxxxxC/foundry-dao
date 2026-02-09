// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Box} from "src/Box.sol";
import {MyGovernor} from "src/MyGovernor.sol";
import {GovToken} from "src/GovToken.sol";
import {TimeLock} from "src/TimeLock.sol";

contract MyGovernorTest is Test {
    MyGovernor public governor;
    GovToken public govToken;
    TimeLock public timelock;
    Box public box;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // NOTE: 1 hour
    uint256 public constant VOTING_DELAY = 1; // NOTE: 1 block
    uint256 public constant VOTING_PERIOD = 50400; // NOTE: ~1 week in blocks (assuming 15s blocks)

    address[] public proposers;
    address[] public executors;
    uint256[] values;
    bytes[] callDatas;
    address[] targets;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCanUpdateBoxWithoutGobernance() public {
        vm.expectRevert();
        box.store(123);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "Store 888 in the Box";
        bytes memory fnData = abi.encodeWithSignature("store(uint256)", valueToStore);
        
        values.push(0);
        callDatas.push(fnData);
        targets.push(address(box));

        // 1. send Propose to DAO
        uint256 proposalId = governor.propose(targets, values, callDatas, description);

        // 2. check the state is Pending
        console.log("Proposal State before block change :", uint256(governor.state(proposalId))); // NOTE: returning the ProposalState enums as uint256
        // assertEq(uint256(governor.state(proposalId)), uint256(0));

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log("Proposal State after block change :", uint256(governor.state(proposalId))); // NOTE: returning the ProposalState enums as uint256

        // 3. Vote
        string memory reason = "I like this proposal";
        uint8 voteWay = 1; // NOTE: VoteType 0 = Against, 1 = For, 2 = Abstain
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 4. Queue TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, callDatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 5. Execute TX
        governor.execute(targets, values, callDatas, descriptionHash);

        // 6. Check the Box number is updated
        console.log("Box number after governance proposal executed :", box.getNUmber());
        assertEq(box.getNUmber(), valueToStore);

    }
}
