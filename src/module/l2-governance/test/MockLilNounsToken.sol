// SPDX-License-Identifier: Unliscensed
pragma solidity ^0.8.19;


import { ERC721Checkpointable } from "nouns-contracts/base/ERC721Checkpointable.sol";
import { ERC721 } from "nouns-contracts/base/ERC721.sol";

contract MockLilNounsToken is ERC721Checkpointable {
    uint256 private _currentNounId;

    constructor() ERC721('Lil Nouns', 'LILNOUN'){}

    function mint() external {
        for (uint256 i = 0; i < 5; i++) {
            _mint(0x035342Fb880F46A9F58343774F131Bf6f6757007, msg.sender, _currentNounId++);
        }
    }
}