// SPDX-License-Identifier: MIT
// Creator: andreitoma8
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IRareBirds is IERC721 {
    function mintFromBreeding(address _to) external;

    function isBird(uint256 _tokenId) external view returns (bool);
}
