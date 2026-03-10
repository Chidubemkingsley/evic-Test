// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/core/ARESTreasury.sol";
import "../src/modules/ProposalModule.sol";
import "../src/modules/TimelockModule.sol";
import "../src/modules/RewardDistributor.sol";
import "../src/modules/GovernanceAttackPrevention.sol";
import "../src/libraries/EIP712.sol";
import "./mocks/MockERC20.sol";

contract ARESTest is Test {
    ARESTreasury public treasury;
    ProposalModule public proposalModule;
    TimelockModule public timelockModule;
    RewardDistributor public rewardDistributor;
    GovernanceAttackPrevention public attackPrevention;

    MockERC20 public testToken;
    MockERC20 public rewardToken;

    address public governor = address(0x1);
    address public proposer = address(0x2);
    address public executor = address(0x3);
    address public recipient = address(0x4);
    address public attacker = address(0x5);

    uint256 public governorPrivateKey = 0xA11CE;
    uint256 public proposerPrivateKey = 0xB0B;
    uint256 public attackerPrivateKey = 0xDEAD;

    function setUp() public {
        governor = vm.addr(governorPrivateKey);
        vm.startPrank(governor);

        testToken = new MockERC20("Test Token", "TEST", 18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);

        attackPrevention = new GovernanceAttackPrevention(
            3,
            1 days,
            1000 ether,
            5,
            7 days
        );

        timelockModule = new TimelockModule(governor, 1 days, 30 days);
        timelockModule.setExecutor(governor, true);

        proposalModule = new ProposalModule(
            governor,
            address(timelockModule),
            2,
            30 days,
            2 days
        );

        rewardDistributor = new RewardDistributor(
            governor,
            address(rewardToken),
            block.timestamp + 90 days
        );

        treasury = new ARESTreasury(governor);

        treasury.initialize(
            payable(address(proposalModule)),
            payable(address(timelockModule)),
            payable(address(rewardDistributor)),
            payable(address(attackPrevention)),
            1000 ether,
            7 days
        );

        testToken.mint(address(treasury), 10000 ether);
        rewardToken.mint(address(rewardDistributor), 10000 ether);

        vm.stopPrank();
    }

    function testUnauthorizedExecution() public {
        vm.startPrank(attacker);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            actionType: 0,
            token: address(testToken),
            recipient: attacker,
            amount: 1000 ether,
            data: ""
        });

        vm.expectRevert(abi.encodeWithSignature("NotGovernor()"));
        treasury.execute(actions);

        vm.stopPrank();
    }

    function testReentrancyProtection() public {
        MaliciousContract malicious = new MaliciousContract(payable(address(treasury)));

        vm.startPrank(governor);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            actionType: 1,
            token: address(0),
            recipient: address(malicious),
            amount: 0,
            data: abi.encodeWithSelector(MaliciousContract.attack.selector)
        });

        vm.expectRevert();
        treasury.execute(actions);

        vm.stopPrank();
    }

    function testDoubleClaimPrevention() public {
        bytes32 leaf = keccak256(abi.encodePacked(recipient, uint256(100 ether), uint256(0)));
        
        vm.prank(governor);
        rewardDistributor.updateMerkleRoot(leaf);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(recipient);
        rewardDistributor.claim(recipient, 100 ether, 0, proof);

        assertTrue(rewardDistributor.hasClaimed(recipient));

        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed()"));
        rewardDistributor.claim(recipient, 100 ether, 0, proof);
    }

    function testMerkleProofVerification() public {
        bytes32 leaf = keccak256(abi.encodePacked(recipient, uint256(500 ether), uint256(1)));
        
        vm.prank(governor);
        rewardDistributor.updateMerkleRoot(leaf);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(recipient);
        rewardDistributor.claim(recipient, 500 ether, 1, proof);

        assertEq(rewardDistributor.getClaimedAmount(recipient), 500 ether);
    }

    function testInvalidSignature() public {
        vm.startPrank(governor);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            actionType: 0,
            token: address(testToken),
            recipient: recipient,
            amount: 1 ether,
            data: ""
        });

        bytes32 digest = EIP712.computeDigest(
            EIP712.hashProposal(0, block.timestamp + 1 days, actions)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        proposalModule.createProposal(actions, block.timestamp + 1 days, signature);

        vm.stopPrank();
    }

    function testTimelockBypass() public {
        vm.startPrank(governor);

        bytes memory callData = abi.encodeWithSelector(
            MockERC20.transfer.selector,
            recipient,
            100 ether
        );

        bytes32 txHash = timelockModule.queueTransaction(
            address(testToken),
            0,
            callData,
            1 days
        );

        vm.warp(block.timestamp + 1 days + 1);

        vm.stopPrank();
        vm.startPrank(attacker);
        
        vm.expectRevert(abi.encodeWithSignature("NotAuthorized()"));
        timelockModule.executeTransaction(
            address(testToken),
            0,
            callData,
            ""
        );

        vm.stopPrank();
    }

    function testTokenMetadata() public {
        assertEq(testToken.name(), "Test Token");
        assertEq(testToken.symbol(), "TEST");
        assertEq(testToken.decimals(), 18);
    }

    function testTimelockExecution() public {
        vm.startPrank(governor);

        bytes memory callData = abi.encodeWithSignature("testCall()");

        bytes32 txHash = timelockModule.queueTransaction(
            address(this),
            0,
            callData,
            1 days
        );

        assertTrue(timelockModule.isQueued(txHash));

        vm.warp(block.timestamp + 1 days + 1);

        timelockModule.executeTransaction(
            address(this),
            0,
            callData,
            ""
        );

        assertTrue(timelockModule.isQueued(txHash) == false);

        vm.stopPrank();
    }

    function testCall() external {
    }
}

contract MaliciousContract {
    ARESTreasury public treasury;

    constructor(address payable _treasury) {
        treasury = ARESTreasury(_treasury);
    }

    function attack() external {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            actionType: 0,
            token: address(0),
            recipient: address(this),
            amount: 1 ether,
            data: ""
        });

        treasury.execute(actions);
    }

    receive() external payable {}
}
