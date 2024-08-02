// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Box} from "../src/Box.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {GovTokens} from "../src/GovTokens.sol";

contract MyGovernorTest is Test {
    MyGovernor private myGoverner;
    Box private box;
    TimeLock private timeLock;
    GovTokens private govTokens;

    address private user = makeAddr("user");
    address private newVoter = makeAddr("newVoter");
    address private proposer = makeAddr("proposer");
    uint256 private constant INITIAL_SUPPLY = 100 ether;

    uint256 private constant MIN_DELAY = 1 hours; // execute a proposer in 1 hour after a vote passed
    address[] private proposers;
    address[] private executors;

    function setUp() external {
        box = new Box();

        govTokens = new GovTokens();
        govTokens.mint(user, INITIAL_SUPPLY);

        vm.startPrank(user);
        // delegate vote power to ourself with INITIAL_SUPPLY
        govTokens.delegate(user);

        timeLock = new TimeLock(MIN_DELAY, proposers, executors);

        myGoverner = new MyGovernor(govTokens, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.DEFAULT_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(myGoverner)); // only governer
        timeLock.grantRole(executorRole, address(0)); // any body can execute
        timeLock.revokeRole(adminRole, user);

        vm.stopPrank();

        box.transferOwnership(address(timeLock));

        govTokens.mint(newVoter, INITIAL_SUPPLY * 2);
        vm.prank(newVoter);
        govTokens.delegate(newVoter);
    }

    function testCantUpdateBoxWithoutGoverance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGoveranceUpdateBox() public {
        // create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(box);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        uint256 newNumber = 1;
        calldatas[0] = abi.encodeWithSelector(box.store.selector, newNumber);
        vm.prank(proposer);
        string memory desc = "store 1 in a box";
        uint256 proposalId = myGoverner.propose(targets, values, calldatas, desc);
        // view the state
        console.log("Proposal state:", uint256(myGoverner.state(proposalId))); // Should be pending

        // pass the votingDelay time
        vm.warp(block.timestamp + myGoverner.votingDelay() + 1);
        vm.roll(block.number + myGoverner.votingDelay() + 1);

        // view the state
        console.log("Proposal state:", uint256(myGoverner.state(proposalId))); // Should be active

        uint8 voteWay = 1; // VoteType.For
        vm.prank(user);
        // vote's weight count by votes (token minted) before a proposal is active !!
        myGoverner.castVoteWithReason(proposalId, voteWay, "love it");

        vm.prank(newVoter);
        // vote's weight count by votes (token minted) before a proposal is active !!
        myGoverner.castVoteWithReason(proposalId, voteWay, "love it too");

        // console.log("user votes:", myGoverner.getVotes(user));
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = myGoverner.proposalVotes(proposalId);
        console.log("forVotes weight:", forVotes);
        console.log("againstVotes weight:", againstVotes);
        console.log("abstainVotes weight:", abstainVotes);

        // pass the voting period
        vm.warp(block.timestamp + myGoverner.votingPeriod() + 1);
        vm.roll(block.number + myGoverner.votingPeriod() + 1);

        bytes32 descHash = keccak256(bytes(desc));
        console.log("Proposal state:", uint256(myGoverner.state(proposalId)));
        // queue the proposal
        myGoverner.queue(targets, values, calldatas, descHash);

        // pass the MIN_DELAY time
        vm.warp(block.timestamp + timeLock.getMinDelay() + 1);
        vm.roll(block.number + timeLock.getMinDelay() + 1);

        // execute the proposal
        myGoverner.execute(targets, values, calldatas, descHash);

        assertEq(box.getNumber(), newNumber);
    }
}
