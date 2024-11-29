// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    uint32 public maximumMinPricePercentage;

    ////////////////////////////////////////////////////////////////////////
    /***************************  EVENTS *********************************/

    event NftAuctionCreated(
        address nftContractAddress,
        uint256 tokenId,
        address nftSeller,
        address erc20Token,
        uint128 minPrice,
        uint128 buyNowPrice,
        uint32 auctionBidPeriod,
        uint32 bidIncreasePercentage
    );
    event BidMade(
        address nftContractAddress,
        uint256 tokenId,
        address bidder,
        uint256 ethAmount,
        address erc20Token,
        uint256 tokenAmount
    );
    event NFTTransferredAndSellerPaid(
        address nftContractAddress,
        uint256 tokenId,
        address nftSeller,
        uint128 nftHighestBid,
        address nftHighestBidder,
        address nftRecipient
    );
    event AuctionPeriodUpdated(
        address nftContractAddress,
        uint256 tokenId,
        uint64 auctionEndPeriod
    );
    event AuctionSettled(
        address nftContractAddress,
        uint256 tokenId,
        address auctionSettler
    );
    event AuctionWithdrawn(
        address nftContractAddress,
        uint256 tokenId,
        address auctionSettler
    );
    event BidWithdrawn(
        address nftContractAddress,
        uint256 tokenId,
        address auctionSettler
    );

    /************************  EVENTS ENDS ******************************/
    ////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////
    /************************  MODIFIERS ******************************/

    modifier isAuctionStartedByOwner(
        address _nftContractAddress,
        uint256 _tokenId
    ) {
        /******** This line is questionable ********/
        require(
            nftAuctions[_nftContractAddress][_tokenId].nftSeller != msg.sender,
            "Auction is already started by owner"
        );

        if (
            nftAuctions[_nftContractAddress][_tokenId].nftSeller != address(0)
        ) {
            require(
                msg.sender == IERC721(_nftContractAddress).ownerOf(_tokenId),
                "Sender doesn't owns NFT"
            );

            // reset auction?
        }
        _;
    }

    modifier priceGreaterThenZero(uint256 _price) {
        require(_price > 0, "Price cannot be 0");
        _;
    }

    modifier isBidIncreasePercentageAboveMinimum(
        uint32 _bidIncreasePercentage
    ) {
        require(
            _bidIncreasePercentage >= minimumSettableIncreasePercentage,
            "Bid increase percentage too low"
        );
        _;
    }

    modifier minPriceDoesNotExceedLimit(
        uint128 _minPrice,
        uint128 _buyNowPrice
    ) {
        require(
            _buyNowPrice == 0 ||
                _getPortionOfBid(_buyNowPrice, maximumMinPricePercentage) >=
                _minPrice,
            "MinPrice > 80% of buyNowPrice"
        );
        _;
    }

    modifier notNftSeller(address _nftContractAddress, uint256 _tokenId) {
        require(
            nftAuctions[_nftContractAddress][_tokenId].nftSeller != msg.sender,
            "Seller cannot bid own NFT"
        );
        _;
    }

    modifier willPaymentBeAccepted(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    ) {
        require(
            _willPaymentBeAccepted(
                _nftContractAddress,
                _tokenId,
                _erc20Token,
                _tokenAmount
            ),
            "Bid to be in specified ERC20/Eth"
        );
        _;
    }

    modifier bidAmountMeetsRequirement(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) {
        require(
            _doesBidAmountMeetsRequirement(
                _nftContractAddress,
                _tokenId,
                _tokenAmount
            ),
            "Not enough funds to bid on NFT"
        );
        _;
    }

    modifier auctionOngoing(address _nftContractAddress, uint256 _tokenId) {
        require(
            _isAuctionOngoing(_nftContractAddress, _tokenId),
            "Auction has ended"
        );
        _;
    }

    modifier notZeroAddress(address _address) {
        require(_address != address(0), "Address should not be a zero address");
        _;
    }

    modifier isAuctionOver(address _nftContractAddress, uint256 _tokenId) {
        require(
            !_isAuctionOngoing(_nftContractAddress, _tokenId),
            "Auction is not over"
        );
        _;
    }

    modifier minimumBidNotMade(address _nftContractAddress, uint256 _tokenId) {
        require(
            !_isMinimumBidMade(_nftContractAddress, _tokenId),
            "The auction has a valid bid made"
        );
        _;
    }

    /************************ MODIFIERS ENDS ***************************/
    //////////////////////////////////////////////////////////////////////////

    function _doesBidAmountMeetsRequirement(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) internal view returns (bool) {
        uint128 buyNowPrice = nftAuctions[_nftContractAddress][_tokenId]
            .buyNowPrice;
        //if buyNowPrice is meet to bid amount
        if (
            buyNowPrice > 0 &&
            (_tokenAmount >= buyNowPrice || msg.value >= buyNowPrice)
        ) {
            return true;
        }
        //if the NFT is up for auction, the bid needs to be a % higher than the previous bid
        uint128 bidIncreaseAmount = (nftAuctions[_nftContractAddress][_tokenId]
            .nftHighestBid *
            (10000 +
                _getBidIncreasePercentage(_nftContractAddress, _tokenId))) /
            10000;
        return (msg.value >= bidIncreaseAmount ||
            _tokenAmount >= bidIncreaseAmount);
    }

    function _willPaymentBeAccepted(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    ) internal returns (bool) {
        address auctionERC20Token = nftAuctions[_nftContractAddress][_tokenId]
            .ERC20Token;

        if (_erc20Token != address(0)) {
            return (msg.value == 0 &&
                auctionERC20Token == _erc20Token &&
                _tokenAmount > 0);
        } else {
            return (msg.value != 0 &&
                _erc20Token == address(0) &&
                _tokenAmount == 0);
        }
    }

    function _isBuyNowPriceMeets(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal view returns (bool) {
        uint128 buyNowPrice = nftAuctions[_nftContractAddress][_tokenId]
            .buyNowPrice;

        return (buyNowPrice > 0 &&
            nftAuctions[_nftContractAddress][_tokenId].nftHighestBid >=
            buyNowPrice);
    }

    function _isMinimumBidMade(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal view returns (bool) {
        uint128 minPrice = nftAuctions[_nftContractAddress][_tokenId].minPrice;

        return (minPrice > 0 &&
            nftAuctions[_nftContractAddress][_tokenId].nftHighestBid >=
            minPrice);
    }

    function _resetAuction(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        nftAuctions[_nftContractAddress][_tokenId].minPrice = 0;
        nftAuctions[_nftContractAddress][_tokenId].buyNowPrice = 0;
        nftAuctions[_nftContractAddress][_tokenId].auctionEnd = 0;
        nftAuctions[_nftContractAddress][_tokenId].auctionBidPeriod = 0;
        nftAuctions[_nftContractAddress][_tokenId].bidIncreasePercentage = 0;
        nftAuctions[_nftContractAddress][_tokenId].nftSeller = address(0);
        nftAuctions[_nftContractAddress][_tokenId].ERC20Token = address(0);
    }

    /*
     * Reset all bid related parameters for an NFT.
     * This effectively sets an NFT as having no active bids
     */
    function _resetBids(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder = address(
            0
        );
        nftAuctions[_nftContractAddress][_tokenId].nftHighestBid = 0;
        nftAuctions[_nftContractAddress][_tokenId].nftRecipient = address(0);
    }

    function _isAuctionOngoing(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal view returns (bool) {
        uint64 auctionEndTimestamp = nftAuctions[_nftContractAddress][_tokenId]
            .auctionEnd;
        return (auctionEndTimestamp == 0 ||
            block.timestamp < auctionEndTimestamp);
    }

    ////////////////////////////////////////////////////////////////////////
    /************************  GETTER FUNCTIONS ******************************/

    /*
     * Returns the percentage of the total bid (used to calculate fee payments)
     */
    function _getPortionOfBid(
        uint256 _totalBid,
        uint256 _percentage
    ) internal pure returns (uint256) {
        return (_totalBid * (_percentage)) / 10000;
    }

    function _getAuctionBidPeriod(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal view returns (uint32) {
        uint32 auctionBidPeriod = nftAuctions[_nftContractAddress][_tokenId]
            .auctionBidPeriod;

        if (auctionBidPeriod == 0) {
            return defaultAuctionBidPeriod;
        } else {
            return auctionBidPeriod;
        }
    }

    function _getBidIncreasePercentage(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal view returns (uint32) {
        uint32 bidIncreasePercentage = nftAuctions[_nftContractAddress][
            _tokenId
        ].bidIncreasePercentage;

        if (bidIncreasePercentage == 0) {
            return defaultBidIncreasePercentage;
        } else {
            return bidIncreasePercentage;
        }
    }

    function _getNftRecipient(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal view returns (address) {
        address recipient = nftAuctions[_nftContractAddress][_tokenId]
            .nftRecipient;

        if (recipient != address(0)) {
            return recipient;
        } else {
            return nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder;
        }
    }

    /************************ GETTER FUNCTIONS ENDS ***************************/
    //////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////
    /************************ CREATE AUCTION ******************************/

    function _setupAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice
    ) internal minPriceDoesNotExceedLimit(_minPrice, _buyNowPrice) {
        if (_erc20Token != address(0)) {
            revert("Provide dealing erc20 token address");
        }

        nftAuctions[_nftContractAddress][_tokenId].ERC20Token = _erc20Token;
        nftAuctions[_nftContractAddress][_tokenId].minPrice = _minPrice;
        nftAuctions[_nftContractAddress][_tokenId].buyNowPrice = _buyNowPrice;
        nftAuctions[_nftContractAddress][_tokenId].nftSeller = msg.sender;
    }

    function _createNewAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice
    ) internal priceGreaterThenZero(_minPrice) {
        _setupAuction(
            _nftContractAddress,
            _tokenId,
            _erc20Token,
            _minPrice,
            _buyNowPrice
        );

        emit NftAuctionCreated(
            _nftContractAddress,
            _tokenId,
            msg.sender,
            _erc20Token,
            _minPrice,
            _buyNowPrice,
            _getAuctionBidPeriod(_nftContractAddress, _tokenId),
            _getBidIncreasePercentage(_nftContractAddress, _tokenId)
        );
    }

    function createNewNftAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        uint32 _auctionBidPeriod,
        uint32 _bidIncreasePercentage
    )
        external
        isAuctionStartedByOwner(_nftContractAddress, _tokenId)
        isBidIncreasePercentageAboveMinimum(_bidIncreasePercentage)
    {
        nftAuctions[_nftContractAddress][_tokenId]
            .bidIncreasePercentage = _bidIncreasePercentage;
        nftAuctions[_nftContractAddress][_tokenId]
            .auctionBidPeriod = _auctionBidPeriod;

        _createNewAuction(
            _nftContractAddress,
            _tokenId,
            _erc20Token,
            _minPrice,
            _buyNowPrice
        );
    }

    function createNewDefaultNftAuction(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice
    ) external isAuctionStartedByOwner(_nftContractAddress, _tokenId) {
        _createNewAuction(
            _nftContractAddress,
            _tokenId,
            _erc20Token,
            _minPrice,
            _buyNowPrice
        );
    }

    /************************ CREATE AUCTION ENDS ***************************/
    //////////////////////////////////////////////////////////////////////////

    // createSale for whiteListBidder

    ////////////////////////////////////////////////////////////////////////
    /************************** BID FUNCTION ******************************/

    function _makeBid(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    )
        internal
        notNftSeller(_nftContractAddress, _tokenId)
        willPaymentBeAccepted(
            _nftContractAddress,
            _tokenId,
            _erc20Token,
            _tokenAmount
        )
        bidAmountMeetsRequirement(_nftContractAddress, _tokenId, _tokenAmount)
    {
        _reversePreviousBidAndUpdateHighestBid(
            _nftContractAddress,
            _tokenId,
            _tokenAmount
        );

        emit BidMade(
            _nftContractAddress,
            _tokenId,
            msg.sender,
            msg.value,
            _erc20Token,
            _tokenAmount
        );
        _updateOngoingAuction(_nftContractAddress, _tokenId);
    }

    function makeBid(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount
    ) external auctionOngoing(_nftContractAddress, _tokenId) {
        _makeBid(_nftContractAddress, _tokenId, _erc20Token, _tokenAmount);
    }

    function makeCustomBid(
        address _nftContractAddress,
        uint256 _tokenId,
        address _erc20Token,
        uint128 _tokenAmount,
        address _nftRecipient
    )
        external
        auctionOngoing(_nftContractAddress, _tokenId)
        notZeroAddress(_nftRecipient)
    {
        nftAuctions[_nftContractAddress][_tokenId].nftRecipient = _nftRecipient;
        _makeBid(_nftContractAddress, _tokenId, _erc20Token, _tokenAmount);
    }

    /************************* BID FUNCTION ENDS ****************************/
    //////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////
    /************************** UPDATE AUCTION ******************************/
    function _updateOngoingAuction(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        if (_isBuyNowPriceMeets(_nftContractAddress, _tokenId)) {
            _transferNftToAuction(_nftContractAddress, _tokenId);
            _transferNftAndPaySeller(_nftContractAddress, _tokenId);
        }

        if (_isMinimumBidMade(_nftContractAddress, _tokenId)) {
            _transferNftToAuction(_nftContractAddress, _tokenId);
            _updateAuctionEnd(_nftContractAddress, _tokenId);
        }
    }

    function _updateAuctionEnd(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        nftAuctions[_nftContractAddress][_tokenId].auctionEnd =
            _getAuctionBidPeriod(_nftContractAddress, _tokenId) +
            uint64(block.timestamp);

        emit AuctionPeriodUpdated(
            _nftContractAddress,
            _tokenId,
            nftAuctions[_nftContractAddress][_tokenId].auctionEnd
        );
    }

    /************************* UPDATE AUCTION ENDS ****************************/
    //////////////////////////////////////////////////////////////////////////

    // reset functions

    ////////////////////////////////////////////////////////////////////////
    /************************** UPDATE BID ******************************/
    function _updateHighestBid(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) internal {
        address auctionERC20Token = nftAuctions[_nftContractAddress][_tokenId]
            .ERC20Token;
        if (auctionERC20Token != address(0)) {
            IERC20(auctionERC20Token).transferFrom(
                msg.sender,
                address(this),
                _tokenAmount
            );
            nftAuctions[_nftContractAddress][_tokenId]
                .nftHighestBid = _tokenAmount;
        } else {
            nftAuctions[_nftContractAddress][_tokenId].nftHighestBid = uint128(
                msg.value
            );
        }
        nftAuctions[_nftContractAddress][_tokenId].nftHighestBidder = msg
            .sender;
    }

    function _reversePreviousBidAndUpdateHighestBid(
        address _nftContractAddress,
        uint256 _tokenId,
        uint128 _tokenAmount
    ) internal {
        address prevHighestBidder = nftAuctions[_nftContractAddress][_tokenId]
            .nftHighestBidder;

        uint128 prevHighestBid = nftAuctions[_nftContractAddress][_tokenId]
            .nftHighestBid;

        _updateHighestBid(_nftContractAddress, _tokenId, _tokenAmount);

        if (prevHighestBidder != address(0)) {
            _payout(
                _nftContractAddress,
                _tokenId,
                prevHighestBidder,
                prevHighestBid
            );
        }
    }

    /************************* UPDATE BID ENDS ****************************/
    //////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////
    /************************** TRANSFER NFT & PAY SELLER  ******************************/
    function _transferNftToAuction(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        address nftSeller = nftAuctions[_nftContractAddress][_tokenId]
            .nftSeller;

        if (IERC721(_nftContractAddress).ownerOf(_tokenId) == nftSeller) {
            IERC721(_nftContractAddress).transferFrom(
                nftSeller,
                address(this),
                _tokenId
            );
            require(
                IERC721(_nftContractAddress).ownerOf(_tokenId) == address(this),
                "nft transfer failed"
            );
        } else {
            require(
                IERC721(_nftContractAddress).ownerOf(_tokenId) == address(this),
                "Seller doesn't own NFT"
            );
        }
    }

    function _transferNftAndPaySeller(
        address _nftContractAddress,
        uint256 _tokenId
    ) internal {
        address nftSeller = nftAuctions[_nftContractAddress][_tokenId]
            .nftSeller;
        address nftHighestBidder = nftAuctions[_nftContractAddress][_tokenId]
            .nftHighestBidder;
        uint128 amount = nftAuctions[_nftContractAddress][_tokenId]
            .nftHighestBid;
        address nftRecipient = _getNftRecipient(_nftContractAddress, _tokenId);

        _resetBids(_nftContractAddress, _tokenId);

        _payout(_nftContractAddress, _tokenId, nftRecipient, amount);

        IERC721(_nftContractAddress).transferFrom(
            address(this),
            nftRecipient,
            _tokenId
        );

        _resetAuction(_nftContractAddress, _tokenId);

        emit NFTTransferredAndSellerPaid(
            _nftContractAddress,
            _tokenId,
            nftSeller,
            amount,
            nftHighestBidder,
            nftRecipient
        );
    }

    function _payout(
        address _nftContractAddress,
        uint256 _tokenId,
        address _recipient,
        uint128 _amount
    ) internal {
        address auctionERC20Token = nftAuctions[_nftContractAddress][_tokenId]
            .ERC20Token;

        if (auctionERC20Token != address(0)) {
            IERC20(auctionERC20Token).transfer(_recipient, _amount);
        } else {
            (bool success, ) = payable(_recipient).call{value: _amount}("");
            if (!success) {
                failedTransferCreadits[_recipient] += _amount;
            }
        }
    }

    /************************* TRANSFER NFT & PAY SELLER ENDS ****************************/
    ///////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////
    /************************** SETTEL & WITHDRAW  ******************************/

    function settelAuction(
        address _nftContractAddress,
        uint256 _tokenId
    ) external isAuctionOver(_nftContractAddress, _tokenId) {
        _transferNftAndPaySeller(_nftContractAddress, _tokenId);

        emit AuctionSettled(_nftContractAddress, _tokenId, msg.sender);
    }

    function withdrawAuction(
        address _nftContractAddress,
        uint256 _tokenId
    ) external {
        require(
            IERC721(_nftContractAddress).ownerOf(_tokenId) == msg.sender,
            "Not NFT owner"
        );
        _resetAuction(_nftContractAddress, _tokenId);
        emit AuctionWithdrawn(_nftContractAddress, _tokenId, msg.sender);
    }

    function withdrawBid(
        address _nftContractAddress,
        uint256 _tokenId
    ) external minimumBidNotMade(_nftContractAddress, _tokenId) {
        address nftHighestBidder = nftAuctions[_nftContractAddress][_tokenId]
            .nftHighestBidder;
        require(msg.sender == nftHighestBidder, "Cannot withdraw funds");

        uint128 nftHighestBid = nftAuctions[_nftContractAddress][_tokenId]
            .nftHighestBid;
        _resetBids(_nftContractAddress, _tokenId);

        _payout(_nftContractAddress, _tokenId, nftHighestBidder, nftHighestBid);

        emit BidWithdrawn(_nftContractAddress, _tokenId, msg.sender);
    }

    /************************* SETTEL & WITHDRAW ENDS ****************************/
    ////////////////////////////////////////////////////////////////////////////////
}
