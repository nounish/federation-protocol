// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NounsFactory} from "src/module/governance-pool/nouns/NounsFactory.sol";
import {NounsPool} from "src/module/governance-pool/nouns/Nouns.sol";
import {FactValidator} from "src/proofs/FactValidator.sol";

contract Deploy is Script {
    // delegate cash has a vanity addr that is static across chains
    address constant DELEGATE_CASH = 0x00000000000076A84feF008CDAbe6409d2FE638B;

    function run() external {
        // default to sepolia
        address reliquary = 0x64357cc3387fF4aAE07B69f2f0a71201532401b4;
        if (block.chainid == 1) {
            reliquary = 0x5E4DE6Bb8c6824f29c44Bd3473d44da120387d08;
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FactValidator fv = new FactValidator();
        NounsPool impl = new NounsPool();

        address feeRecipient = msg.sender;
        uint256 feeBPS = 1000;
        uint256 maxBasefeeRefund = 80 gwei;
        uint256 useStartBlockFromPropId = 0;

        NounsFactory factory = new NounsFactory(
            address(impl),
            reliquary,
            DELEGATE_CASH,
            address(fv),
            feeRecipient,
            feeBPS,
            maxBasefeeRefund,
            useStartBlockFromPropId
        );

        console2.log("fact validator:", address(fv));
        console2.log("pool impl:", address(impl));
        console2.log("pool factory:", address(factory));

        vm.stopBroadcast();
    }
}
