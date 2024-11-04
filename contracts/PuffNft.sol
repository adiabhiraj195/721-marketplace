// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PuffNFTs is ERC721, Ownable {
    uint256 private s_tokenIds = 0;
    mapping(uint256 => string) private s_tokenURIs;

    constructor() ERC721("PuffNFT", "PNT") Ownable(msg.sender) {}

    function mintNFT(
        address _recipient,
        string memory _tokenURI
    ) public onlyOwner returns (uint256) {
        s_tokenIds++;

        uint256 newItemId = s_tokenIds;
        _mint(_recipient, newItemId);
        _setTokenURI(newItemId, _tokenURI);

        return newItemId;
    }

    function _setTokenURI(uint256 _tokenId, string memory _tokenURI) internal {
        s_tokenURIs[_tokenId] = _tokenURI;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return s_tokenURIs[_tokenId];
    }
}
