// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// listItem: List NFTs on the marketplace ✅
// buyItem: Buy the NFTS✅
// cancelItem: Cancel a listing✅
// updateListing: Update Price✅
// withdrawProceeds: Withdraw payment for my bought NFTs✅

error PriceMustBeAboveZero();
error NotApprovedForMarketplace();
error AlreadyListed(address nftAddress, uint256 tokenId);
error NotOwner();
error NotListed(address nftAddress, uint256 tokenId);
error AlreadyBuyed();
error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error NoProceeds();

contract NftMarketplace {
    struct Listing {
        uint256 price;
        address seller;
    }

    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );
    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );
    event ItemDeleted(
        address indexed owner,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    mapping(address => mapping(uint256 => Listing)) private s_listings;
    mapping(address => uint256) private s_sellerToBalance;

    modifier notListed(address nftAddress, uint256 tokenId) {
        Listing memory item = s_listings[nftAddress][tokenId];
        if (item.price > 0) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwner(
        address nftAddress,
        uint256 tokenId,
        address sender
    ) {
        IERC721 nft = IERC721(nftAddress);
        if (nft.ownerOf(tokenId) != sender) {
            revert NotOwner();
        }
        _;
    }
    modifier notOwner(
        address nftAddress,
        uint256 tokenId,
        address sender
    ) {
        IERC721 nft = IERC721(nftAddress);
        if (nft.ownerOf(tokenId) == sender) {
            revert AlreadyBuyed();
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory item = s_listings[nftAddress][tokenId];

        if (item.price <= 0) revert NotListed(nftAddress, tokenId);
        _;
    }

    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    )
        external
        notListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        if (price <= 0) revert PriceMustBeAboveZero();

        IERC721 nft = IERC721(nftAddress);
        if (nft.getApproved(tokenId) != address(this)) {
            revert NotApprovedForMarketplace();
        }

        s_listings[nftAddress][tokenId] = Listing(price, msg.sender);
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    function buyItem(
        address nftAddress,
        uint256 tokenId
    )
        external
        payable
        // nonReentrant
        isListed(nftAddress, tokenId)
        notOwner(nftAddress, tokenId, msg.sender)
    {
        Listing memory item = s_listings[nftAddress][tokenId];

        if (msg.value < item.price) {
            revert PriceNotMet(nftAddress, tokenId, item.price);
        }

        s_sellerToBalance[item.seller] += msg.value;
        delete (s_listings[nftAddress][tokenId]);

        IERC721(nftAddress).safeTransferFrom(item.seller, msg.sender, tokenId);

        emit ItemBought(msg.sender, nftAddress, tokenId, msg.value);
    }

    function cancelListing(
        address nftAddress,
        uint256 tokenId
    )
        external
        isListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        delete (s_listings[nftAddress][tokenId]);
        emit ItemDeleted(msg.sender, nftAddress, tokenId);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    )
        external
        isListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        if (newPrice <= 0) {
            revert PriceMustBeAboveZero();
        }

        s_listings[nftAddress][tokenId].price = newPrice;

        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
    }

    function withdrawProceeds() external {
        uint256 amount = s_sellerToBalance[msg.sender];

        if (amount <= 0) {
            revert NoProceeds();
        }
        s_sellerToBalance[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }

    // getter function

    function getListing(
        address nftAddress,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return s_listings[nftAddress][tokenId];
    }

    function getBalance() external view returns (uint256) {
        return s_sellerToBalance[msg.sender];
    }
}
