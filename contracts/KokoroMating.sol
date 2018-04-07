// -------------------------------------------------------------------
// @title A facet of KokoroCore that manages Kokoro mating, 
//  pregnation, and birth.
// @author Gen0 (https://www.gen0.io)
// @dev See the KokoroCore contract documentation to understand how 
//  the various contract facets are arranged.
//
// -------------------------------------------------------------------

contract KokoroMating is KokoroOwnership {

    // @dev The Pregnant event is fired when two kokoros successfully mate and the pregnancy
    //  timer begins for the matron.
    event Pregnant(address owner, uint256 matronId, uint256 sireId, uint256 cooldownEndBlock);

    // @notice The minimum payment required to use mateWithAuto(). This fee goes towards
    //  the gas cost paid by whatever calls giveBirth(), and can be dynamically updated by
    //  the COO role as the gas price changes.
    // @dev TODO
    uint256 public autoBirthFee = 2 finney;

    // Keeps track of number of pregnant kokoros.
    uint256 public pregnantKokoros;

    // @dev The address of the sibling contract that is used to implement the 
    //  genetic combination algorithm.
    GeneScienceInterface public geneScience;

    // @dev Update the address of the genetic contract, can only be called by the CEO.
    // @param _address An address of a GeneScience contract instance to be used from this point forward.
    function setGeneScienceAddress(address _address) external onlyCEO {
        GeneScienceInterface candidateContract = GeneScienceInterface(_address);

        // NOTE: verify that a contract is what we expect - https://github.com/Lunyr/crowdsale-contracts/blob/cfadd15986c30521d8ba7d5b6f57b4fefcc7ac38/contracts/LunyrToken.sol#L117
        require(candidateContract.isGeneScience());

        // Set the new contract address
        geneScience = candidateContract;
    }

    // @dev Checks that a given kokoro is able to mate. Requires that the
    //  current cooldown is finished (for sires) and also checks that there is
    //  no pending pregnancy.
    function _isReadyToMate(Kokoro _kokoro) internal view returns (bool) {
        return (_kokoro.siringWithId == 0) && (_kokoro.cooldownEndBlock <= uint64(block.number));
    }

    // @dev Check if a sire has authorized mating with this matron. True if both sire
    //  and matron have the same owner, or if the sire has given siring permission to
    //  the matron's owner (via approveSiring()).
    function _isSiringPermitted(uint256 _sireId, uint256 _matronId) internal view returns (bool) {
        address matronOwner = kokoroIndexToOwner[_matronId];
        address sireOwner = kokoroIndexToOwner[_sireId];

        // Siring is okay if they have same owner, or if the matron's owner was given
        // permission to mate with this sire.
        return (matronOwner == sireOwner || sireAllowedToAddress[_sireId] == matronOwner);
    }

    // @dev Set the cooldownEndTime for the given Kokoro, based on its current cooldownIndex.
    //  Also increments the cooldownIndex (unless it has hit the cap).
    // @param _kokoro A reference to the Kokoro in storage which needs its timer started.
    function _triggerCooldown(Kokoro storage _kokoro) internal {
        // Compute an estimation of the cooldown time in blocks (based on current cooldownIndex).
        _kokoro.cooldownEndBlock = uint64((cooldowns[_kokoro.cooldownIndex]/secondsPerBlock) + block.number);

        // Increment the mating count, clamping it at 13, which is the length of the
        // cooldowns array. We could check the array size dynamically, but hard-coding
        // this as a constant saves gas. 
        if (_kokoro.cooldownIndex < 13) {
            _kokoro.cooldownIndex += 1;
        }
    }

    // @notice Grants approval to another user to sire with one of your Kokoros.
    // @param _addr The address that will be able to sire with your Kokoro. Set to
    //  address(0) to clear all siring approvals for this Kokoro.
    // @param _sireId A Kokoro that you own that _addr will now be able to sire with.
    function approveSiring(address _addr, uint256 _sireId)
        external
        whenNotPaused
    {
        require(_owns(msg.sender, _sireId));
        sireAllowedToAddress[_sireId] = _addr;
    }

    // @dev Updates the minimum payment required for calling giveBirthAuto(). Can only
    //  be called by the COO address. (This fee is used to offset the gas cost incurred
    //  by the autobirth daemon).
    function setAutoBirthFee(uint256 val) external onlyCOO {
        autoBirthFee = val;
    }

    // @dev Checks to see if a given Kokoro is pregnant and (if so) if the pregnation
    //  period has passed.
    function _isReadyToGiveBirth(Kokoro _matron) private view returns (bool) {
        return (_matron.siringWithId != 0) && (_matron.cooldownEndBlock <= uint64(block.number));
    }

    // @notice Checks that a given kokoro is able to mate (i.e. it is not pregnant or
    //  in the middle of a siring cooldown).
    // @param _kokoroId reference the id of the kokoro, any user can inquire about it
    function isReadyToMate(uint256 _kokoroId)
        public
        view
        returns (bool)
    {
        require(_kokoroId > 0);
        Kokoro storage kokoro = kokoros[_kokoroId];
        return _isReadyToMate(kokoro);
    }

    // @dev Checks whether a kokoro is currently pregnant.
    // @param _kokoroId reference the id of the kokoro, any user can inquire about it
    function isPregnant(uint256 _kokoroId)
        public
        view
        returns (bool)
    {
        require(_kokoroId > 0);
        // A kokoro is pregnant if and only if this field is set
        return kokoros[_kokoroId].siringWithId != 0;
    }

    // @dev Internal check to see if a given sire and matron are a valid mating pair. DOES NOT
    //  check ownership permissions (that is up to the caller).
    // @param _matron A reference to the Kokoro struct of the potential matron.
    // @param _matronId The matron's ID.
    // @param _sire A reference to the Kokoro struct of the potential sire.
    // @param _sireId The sire's ID
    function _isValidMatingPair(
        Kokoro storage _matron,
        uint256 _matronId,
        Kokoro storage _sire,
        uint256 _sireId
    )
        private
        view
        returns(bool)
    {
        // Can't mate with itself
        if (_matronId == _sireId) {
            return false;
        }

        // Kokoros can't breed with their parents.
        if (_matron.matronId == _sireId || _matron.sireId == _sireId) {
            return false;
        }
        if (_sire.matronId == _matronId || _sire.sireId == _matronId) {
            return false;
        }

        // We can short circuit the sibling check (below) if either kokoro is
        // gen 0 (has a matron ID of zero).
        if (_sire.matronId == 0 || _matron.matronId == 0) {
            return true;
        }

        // Kokoros can't breed with full or half siblings.
        if (_sire.matronId == _matron.matronId || _sire.matronId == _matron.sireId) {
            return false;
        }
        if (_sire.sireId == _matron.matronId || _sire.sireId == _matron.sireId) {
            return false;
        }

        return true;
    }

    // @dev Internal check to see if a given sire and matron are a valid mating pair for
    //  mating via auction (i.e. skips ownership and siring approval checks).
    // TODO
    function _canMateWithViaAuction(uint256 _matronId, uint256 _sireId)
        internal
        view
        returns (bool)
    {
        Kokoro storage matron = kokoros[_matronId];
        Kokoro storage sire = kokoros[_sireId];
        return _isValidMatingPair(matron, _matronId, sire, _sireId);
    }

    // @notice Checks to see if two kokoros can breed together, including checks for
    //  ownership and siring approvals. Does NOT check that both cats are ready for
    //  mating (i.e. mateWith could still fail until the cooldowns are finished).
    //  TODO: Shouldn't this check pregnancy and cooldowns?!?
    // @param _matronId The ID of the proposed matron.
    // @param _sireId The ID of the proposed sire.
    function canMateWith(uint256 _matronId, uint256 _sireId)
        external
        view
        returns(bool)
    {
        require(_matronId > 0);
        require(_sireId > 0);
        Kokoro storage matron = kokoros[_matronId];
        Kokoro storage sire = kokoros[_sireId];
        return _isValidMatingPair(matron, _matronId, sire, _sireId) &&
            _isSiringPermitted(_sireId, _matronId);
    }

    // @dev Internal utility function to initiate breeding, assumes that all breeding
    //  requirements have been checked.
    function _mateWith(uint256 _matronId, uint256 _sireId) internal {
        Kokoro storage sire = kokoros[_sireId];
        Kokoro storage matron = kokoros[_matronId];

        // Mark the matron as pregnant, keeping track of who the sire is.
        matron.siringWithId = uint32(_sireId);

        // Trigger the cooldown for both parents.
        _triggerCooldown(sire);
        _triggerCooldown(matron);

        // Clear siring permission for both parents. This may not be strictly necessary
        delete sireAllowedToAddress[_matronId];
        delete sireAllowedToAddress[_sireId];

        pregnantKokoros++;

        // Emit the pregnancy event.
        Pregnant(kokorosIndexToOwner[_matronId], _matronId, _sireId, matron.cooldownEndBlock);
    }

    // @notice Breed a Kokoros you own (as matron) with a sire that you own, or for which 
    //  you have previously been given Siring approval. Will either make your cat pregnant, 
    //  or will fail entirely. Requires a pre-payment of the fee given out to the first 
    //  caller of giveBirth()
    // @param _matronId The ID of the Kokoro acting as matron (will end up pregnant if successful)
    // @param _sireId The ID of the Kokoro acting as sire (will begin its siring cooldown if successful)
    function mateWithAuto(uint256 _matronId, uint256 _sireId)
        external
        payable
        whenNotPaused
    {
        // Checks for payment.
        require(msg.value >= autoBirthFee);

        // Caller must own the matron.
        require(_owns(msg.sender, _matronId));

        // Neither sire nor matron are allowed to be on auction during a normal
        // mating operation, but we don't need to check that explicitly.

        // Check that matron and sire are both owned by caller, or that the sire
        // has given siring permission to caller (i.e. matron's owner).
        // Will fail for _sireId = 0
        require(_isSiringPermitted(_sireId, _matronId));

        // Grab a reference to the potential matron
        Kokoro storage matron = kokoros[_matronId];

        require(_isReadyToMate(matron));

        Kokoro storage sire = kokoros[_sireId];

        require(_isReadyToMate(sire));

        require(_isValidMatingPair(
            matron,
            _matronId,
            sire,
            _sireId
        ));

        _mateWith(_matronId, _sireId);
    }

    // @notice Have a pregnant Kokoro give birth!
    // @param _matronId A Kokoro ready to give birth.
    // @return The Kokoro ID of the new kokoro.
    // @dev Looks at a given Kokoro and, if pregnant and if the pregnation period has 
    //  passed, combines the genes of the two parents to create a new kokoro. The new 
    //  Kokoro is assigned to the current owner of the matron. Upon successful completion, 
    //  both the matron and the new kokoro will be ready to breed again. Note that anyone 
    //  can call this function (if they are willing to pay the gas!), but the new kokoro 
    //  always goes to the mother's owner.
    function giveBirth(uint256 _matronId)
        external
        whenNotPaused
        returns(uint256)
    {
        // Grab a reference to the matron in storage.
        Kokoro storage matron = kokoros[_matronId];

        require(matron.birthTime != 0);
        require(_isReadyToGiveBirth(matron));

        // Grab a reference to the sire in storage.
        uint256 sireId = matron.siringWithId;
        Kokoro storage sire = kokoros[sireId];

        // Determine the higher generation number of the two parents
        uint16 parentGen = matron.generation;
        if (sire.generation > matron.generation) {
            parentGen = sire.generation;
        }

        // Call the gene mixing operation.
        uint256 childGenes = geneScience.mixGenes(matron.genes, sire.genes, matron.cooldownEndBlock - 1);

        // Make the new kokoro
        address owner = kokoroIndexToOwner[_matronId];
        uint256 kokoroId = _createKokoro(_matronId, matron.siringWithId, parentGen + 1, childGenes, owner);

        // Clear the reference to sire from the matron (REQUIRED! Having siringWithId
        // set is what marks a matron as being pregnant.)
        delete matron.siringWithId;

        pregnantKokoros--;

        // Send the balance fee to the person who made birth happen.
        msg.sender.send(autoBirthFee);

        // return the new kokoro's ID
        return kokoroId;
    }
}
