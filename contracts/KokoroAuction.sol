// -------------------------------------------------------------------
// @title Handles creating auctions for sale and siring of kokoros.
//  This wrapper of ReverseAuction exists only so that users can create
//  auctions with only one transaction.
// @author Gen0 (https://www.gen0.io)
// @dev See the KokoroCore contract documentation to understand how 
//  the various contract facets are arranged.
//
// -------------------------------------------------------------------

contract KokoroAuction is KokoroMating {

    // @notice The auction contract variables are defined in KokoroFactory to allow
    //  us to refer to them in KokoroOwnership to prevent accidental transfers.
    // `saleAuction` refers to the auction for gen0 and p2p sale of kokoros.
    // `siringAuction` refers to the auction for siring rights of kokoros.

    /// @dev Sets the reference to the sale auction.
    /// @param _address - Address of sale contract.
    function setSaleAuctionAddress(address _address) external onlyCEO {
        SaleClockAuction candidateContract = SaleClockAuction(_address);

        // NOTE: verify that a contract is what we expect - https://github.com/Lunyr/crowdsale-contracts/blob/cfadd15986c30521d8ba7d5b6f57b4fefcc7ac38/contracts/LunyrToken.sol#L117
        require(candidateContract.isSaleClockAuction());

        // Set the new contract address
        saleAuction = candidateContract;
    }

    /// @dev Sets the reference to the siring auction.
    /// @param _address - Address of siring contract.
    function setSiringAuctionAddress(address _address) external onlyCEO {
        SiringClockAuction candidateContract = SiringClockAuction(_address);

        // NOTE: verify that a contract is what we expect - https://github.com/Lunyr/crowdsale-contracts/blob/cfadd15986c30521d8ba7d5b6f57b4fefcc7ac38/contracts/LunyrToken.sol#L117
        require(candidateContract.isSiringClockAuction());

        // Set the new contract address
        siringAuction = candidateContract;
    }

    // @dev Put a kokoro up for auction.
    //  Does some ownership trickery to create auctions in one tx.
    function createSaleAuction(
        uint256 _kokoroId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration
    )
        external
        whenNotPaused
    {
        // Auction contract checks input sizes
        // If kokoro is already on any auction, this will throw
        // because it will be owned by the auction contract.
        require(_owns(msg.sender, _kokoroId));
        // Ensure the kokoro is not pregnant to prevent the auction
        // contract accidentally receiving ownership of the child.
        // NOTE: the kokoro IS allowed to be in a cooldown.
        require(!isPregnant(_kokoroId));
        _approve(_kokoroId, saleAuction);
        // Sale auction throws if inputs are invalid and clears
        // transfer and sire approval after escrowing the kokoro.
        saleAuction.createAuction(
            _kokoroId,
            _startingPrice,
            _endingPrice,
            _duration,
            msg.sender
        );
    }

    // @dev Put a kokoro up for auction to be sire.
    //  Performs checks to ensure the kokoro can be sired, then
    //  delegates to reverse auction.
    function createSiringAuction(
        uint256 _kokoroId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration
    )
        external
        whenNotPaused
    {
        // Auction contract checks input sizes
        // If kokoro is already on any auction, this will throw
        // because it will be owned by the auction contract.
        require(_owns(msg.sender, _kokoroId));
        require(isReadyToMate(_kokoroId));
        _approve(_kokoroId, siringAuction);
        // Siring auction throws if inputs are invalid and clears
        // transfer and sire approval after escrowing the kokoro.
        siringAuction.createAuction(
            _kokoroId,
            _startingPrice,
            _endingPrice,
            _duration,
            msg.sender
        );
    }

    // @dev Completes a siring auction by bidding.
    //  Immediately breeds the winning matron with the sire on auction.
    // @param _sireId - ID of the sire on auction.
    // @param _matronId - ID of the matron owned by the bidder.
    function bidOnSiringAuction(
        uint256 _sireId,
        uint256 _matronId
    )
        external
        payable
        whenNotPaused
    {
        // Auction contract checks input sizes
        require(_owns(msg.sender, _matronId));
        require(isReadyToMate(_matronId));
        require(_canMateWithViaAuction(_matronId, _sireId));

        // Define the current price of the auction.
        uint256 currentPrice = siringAuction.getCurrentPrice(_sireId);
        require(msg.value >= currentPrice + autoBirthFee);

        // Siring auction will throw if the bid fails.
        siringAuction.bid.value(msg.value - autoBirthFee)(_sireId);
        _breedWith(uint32(_matronId), uint32(_sireId));
    }

    // @dev Transfers the balance of the sale auction contract
    // to the KokoroCore contract. We use two-step withdrawal to
    // prevent two transfer calls in the auction bid function.
    function withdrawAuctionBalances() external onlyCLevel {
        saleAuction.withdrawBalance();
        siringAuction.withdrawBalance();
    }
}
