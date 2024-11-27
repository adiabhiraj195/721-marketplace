// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract PuffAuction {
    mapping(address => mapping(uint256 => Auction)) public nftAuctions;
    mapping(address => uint256) public failedTransferCreadits;

    struct Auction {
        uint32 bidIncreasePercentage;
        uint32 auctionBidPeriod; //Increment in Time frame after every bid placed for the next bid
        uint64 auctionEnd;
        uint128 minPrice;
        uint128 buyNowPrice;
        uint128 nftHighestBid;
        address nftHighestBidder;
        address nftSeller;
        //  address whitelistedBuyer;
        address nftRecipient; //The bidder can specify a recipient for the NFT if their bid is successful.
        address ERC20Token;
        // address[] feeRecipients;
        // uint32[] feePercentages;
    }

    /****** Default values ******/
    uint32 public defaultBidIncreasePercentage;
    uint32 public minimumSettableIncreasePercentage;
    uint32 public defaultAuctionBidPeriod;

    /*╔═════════════════════════════╗
       ║           EVENTS            ║
       ╚═════════════════════════════╝*/
    event AuctionCreated (
        
    )
    /*╔═════════════════════════════╗
       ║           EVENTS            ║
       ║            ENDS             ║
       ╚═════════════════════════════╝*/

    /*╔═════════════════════════════╗
       ║           MODIFIERS         ║
       ╚═════════════════════════════╝*/


    // create auction 
    // createSale
    // make bid
    // update auction
    // reset functions
    // update bids
    // transfer nft & pay seller
    // settel & withdraw
    
}
