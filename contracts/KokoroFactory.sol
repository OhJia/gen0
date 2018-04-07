// -------------------------------------------------------------------
// @title Base contract for Kokoro. Holds all common structs, events 
//  and base variables.
// @author Gen0 (https://www.gen0.io)
// @dev See the KokoroCore contract documentation to understand how 
//  the various contract facets are arranged.
//
// -------------------------------------------------------------------

contract KokoroFactory is KokoroAccessControl {

    // ------------------------------
    // EVENTS
    // ------------------------------

    // @dev The Birth event is fired whenever a new Kokoro comes into existence. 
    // Called when a new Kokoro is created.
    event Birth(address owner, uint256 kokoroId, uint256 matronId, uint256 sireId, uint256 genes);

    // @dev Transfer event as defined in current draft of ERC721. 
    // Emitted every time a Kokoro ownership is assigned, including births.
    event Transfer(address from, address to, uint256 tokenId);

    // ------------------------------
    // DATA TYPES
    // ------------------------------

    // @dev The main Kokoro struct. Every Kokoro is represented by a copy
    //  of this structure.
    struct Kokoro {
        uint256 genes;
        uint64 birthTime;
        uint64 cooldownEndBlock;
        uint32 matronId;
        uint32 sireId;
        uint32 siringWithId;
        uint16 cooldownIndex;
        uint16 generation;
    }

    // ------------------------------
    // CONSTANTS
    // ------------------------------

    // @dev A lookup table indicating the cooldown duration after any successful
    //  breeding action, called "pregnancy time" for matrons and "siring cooldown"
    //  for sires. 
    uint32[14] public constant COOLDOWNS = [
        uint32(1 minutes),
        uint32(2 minutes),
        uint32(5 minutes),
        uint32(10 minutes),
        uint32(30 minutes),
        uint32(1 hours),
        uint32(2 hours),
        uint32(4 hours),
        uint32(8 hours),
        uint32(16 hours),
        uint32(1 days),
        uint32(2 days),
        uint32(4 days),
        uint32(7 days)
    ];

    // An approximation of currently how many seconds are in between blocks.
    uint256 public secondsPerBlock = 15;

    // ------------------------------
    // STORAGE
    // ------------------------------

    // @dev An array containing the Kokoro struct for all Kokoros in existence. The ID
    //  of each Kokoro is actually an index into this array. 
    Kokoro[] kokoros;

    // @dev A mapping from Kokoro IDs to the address that owns them. All Kokoros have
    //  some valid owner address, even gen0 are created with a non-zero owner.
    mapping (uint256 => address) public kokoroIndexToOwner;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping (address => uint256) ownershipTokenCount;

    // @dev A mapping from KokoroIDs to an address that has been approved to call
    //  transferFrom(). Each Kokoro can only have one approved address for transfer
    //  at any time. A zero value means no approval is outstanding.
    mapping (uint256 => address) public kokoroIndexToApproved;

    // @dev A mapping from KokoroIDs to an address that has been approved to use
    //  this Kokoro for siring via breedWith(). Each Kokoro can only have one approved
    //  address for siring at any time. A zero value means no approval is outstanding.
    mapping (uint256 => address) public sireAllowedToAddress;

    // @dev The address of the ClockAuction contract that handles sales of Kokoros. This
    //  same contract handles both peer-to-peer sales as well as the gen0 sales which are
    //  initiated every 15 minutes.
    SaleClockAuction public saleAuction;

    // @dev The address of a custom ClockAuction subclassed contract that handles siring
    //  auctions. Needs to be separate from saleAuction because the actions taken on success
    //  after a sales and siring auction are quite different.
    SiringClockAuction public siringAuction;

    // @dev Assigns ownership of a specific Kokoro to an address.
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // Since the number of kokoros is capped to 2^32 we can't overflow this
        ownershipTokenCount[_to]++;
        // transfer ownership
        kokoroIndexToOwner[_tokenId] = _to;
        // When creating new kokoros _from is 0x0, but we can't account that address.
        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
            // once the kokoro is transferred also clear sire allowances
            delete sireAllowedToAddress[_tokenId];
            // clear any previously approved ownership exchange
            delete kokoroIndexToApproved[_tokenId];
        }
        // Emit the transfer event.
        Transfer(_from, _to, _tokenId);
    }

    // @dev An internal method that creates a new kokoro and stores it. This
    //  method doesn't do any checking and should only be called when the
    //  input data is known to be valid. Will generate both a Birth event
    //  and a Transfer event.
    // @param _matronId The Kokoro ID of the matron of this cat (zero for gen0)
    // @param _sireId The Kokoro ID of the sire of this cat (zero for gen0)
    // @param _generation The generation number of this cat, must be computed by caller.
    // @param _genes The Kokoro's genetic code.
    // @param _owner The inital owner of this Kokoro, must be non-zero (except for the unKokoro, ID 0)
    function _createKokoro(
        uint256 _matronId,
        uint256 _sireId,
        uint256 _generation,
        uint256 _genes,
        address _owner
    )
        internal
        returns (uint)
    {
        require(_matronId == uint256(uint32(_matronId)));
        require(_sireId == uint256(uint32(_sireId)));
        require(_generation == uint256(uint16(_generation)));

        // New Kokoro starts with the same cooldown as parent gen/2
        uint16 cooldownIndex = uint16(_generation / 2);
        if (cooldownIndex > 13) {
            cooldownIndex = 13;
        }

        Kokoro memory _kokoro = Kokoro({
            genes: _genes,
            birthTime: uint64(now),
            cooldownEndBlock: 0,
            matronId: uint32(_matronId),
            sireId: uint32(_sireId),
            siringWithId: 0,
            cooldownIndex: cooldownIndex,
            generation: uint16(_generation)
        });
        uint256 newKokoroId = kokoros.push(_kokoro) - 1;

        // Just to be sure
        require(newKokoroId == uint256(uint32(newKokoroId)));

        // emit the birth event
        Birth(
            _owner,
            newKokoroId,
            uint256(_kokoro.matronId),
            uint256(_kokoro.sireId),
            _kokoro.genes
        );

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(0, _owner, newKokoroId);

        return newKokoroId;
    }

    // Any C-level can fix how many seconds per blocks are currently observed.
    function setSecondsPerBlock(uint256 secs) external onlyCLevel {
        require(secs < cooldowns[0]);
        secondsPerBlock = secs;
    }
}
