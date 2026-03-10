// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/core/ARESTreasury.sol";
import "../src/modules/ProposalModule.sol";
import "../src/modules/TimelockModule.sol";
import "../src/modules/RewardDistributor.sol";
import "../src/modules/GovernanceAttackPrevention.sol";
import "../test/mocks/MockERC20.sol"; 

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address governor = vm.addr(deployerPrivateKey);

        
        MockERC20 aresToken = new MockERC20("ARES Protocol Token", "ARES", 18);

        GovernanceAttackPrevention attackPrevention = new GovernanceAttackPrevention(
            3,
            1 days,
            1000 ether,
            5,
            7 days
        );

        TimelockModule timelockModule = new TimelockModule(
            governor,
            1 days,
            30 days
        );
        timelockModule.setExecutor(governor, true);

        ProposalModule proposalModule = new ProposalModule(
            governor,
            address(timelockModule),
            2,
            30 days,
            2 days
        );

        
        RewardDistributor rewardDistributor = new RewardDistributor(
            governor,
            address(aresToken), 
            block.timestamp + 90 days
        );

        ARESTreasury treasury = new ARESTreasury(governor);

        treasury.initialize(
            payable(address(proposalModule)),
            payable(address(timelockModule)),
            payable(address(rewardDistributor)),
            payable(address(attackPrevention)),
            1000 ether,
            7 days
        );

        
        aresToken.mint(address(treasury), 500_000_000 ether);

        vm.stopBroadcast();

        console.log("Mock ARES Token:", address(aresToken));
        console.log("GovernanceAttackPrevention:", address(attackPrevention));
        console.log("TimelockModule:", address(timelockModule));
        console.log("ProposalModule:", address(proposalModule));
        console.log("RewardDistributor:", address(rewardDistributor));
        console.log("ARESTreasury:", address(treasury));
    }
}
