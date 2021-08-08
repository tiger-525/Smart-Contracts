// Altura - LootBox contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "@chainlink/contracts/src/v0.8/dev/VRFConsumerBase.sol";

interface IAlturaNFT {
	function safeTransferFrom(address from,
			address to,
			uint256 id,
			uint256 amount,
			bytes calldata data) external;
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external;
	function mint(address to, uint256 id, uint256 amount) external returns(bool);
	function balanceOf(address account, uint256 id) external view returns (uint256);
}

contract AlturaLootbox is ERC1155Holder, VRFConsumerBase  {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;


    bytes32 internal vrfKeyHash;
    uint256 internal vrfFee;

    /**
        Card Struct
     */
    struct Card {
        address collectionId;   // collection address
        uint256 tokenId;        // token id of collection
    }

    /**
     * Round Struct
     */
    struct Round {
        uint256 id; // request id.
        address player; // address of player.
        RoundStatus status; // status of the round.
        uint256 times; // how many times of this round;
        uint256 totalTimes; // total time of an account.
        bytes32[20] cards; // Prize card of this round.
        uint256 lastUpdated;
    }

    enum RoundStatus { Initial, Pending, Finished } // status of this round
    mapping(address => Round) public gameRounds;
    mapping(bytes32 => address) private _vrfRequests;

    uint256 public currentRoundIdCount; //until now, the total round of this Lootbox.
    uint256 public totalRoundCount;

    string public boxName;
    string public boxUri;
    IERC1155 public paymentCollection;
    uint256 public paymentTokenId;
    uint256 public playOncePrice;
    uint256 public itemsPerSpin;
    
    address public factory;
    address public owner;
    address public paymentAddress;

    bool public maintaining = false;
    bool public banned = false;

    // This is a set which contains cardKey
    mapping(bytes32 => Card) private _cards;
    EnumerableSet.Bytes32Set private _cardIndices;

    
    // This mapping contains cardKey => amount
    mapping(bytes32 => uint256) public amountWithId;
    // Prize pool with a random number to cardKey
    mapping(uint256 => bytes32) private _prizePool;
    // The amount of cards in this lootbox.
    uint256 public cardAmount;

    uint256 private _salt;
    uint256 public shuffleCount = 20;


    EnumerableSet.AddressSet private _staffAccountSet;
    

    event AddToken(bytes32 key, address collectionId, uint256 tokenId, uint256 amount, uint256 cardAmount);
    event AddTokenBatch(bytes32[] keys, address[] collections, uint256[] tokenIds, uint256[] amounts, uint256 cardAmount);
    event RemoveCard(uint256 card, uint256 removeAmount, uint256 cardAmount);
    event SpinLootbox(address account, uint256 times, uint256 playFee);

    event LootboxLocked(bool locked);

    /**
     * Constructor inherits VRFConsumerBase
     * 
     * Network: Binance Mainnet
     * Chainlink VRF Coordinator address: 0x747973a5A2a4Ae1D3a8fDF5479f1514F65Db9C31
     * LINK token address:                0x404460C6A5EdE2D891e8297795264fDe62ADBB75
     * Key Hash: 0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c
     * Fee: 0.2 LINK
     */
    constructor() 
        VRFConsumerBase(
            0x747973a5A2a4Ae1D3a8fDF5479f1514F65Db9C31, // VRF Coordinator
            0x404460C6A5EdE2D891e8297795264fDe62ADBB75  // LINK Token
        ) {
        factory = msg.sender;

        vrfKeyHash = 0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c;
        vrfFee = 0.2 * 10 ** 18; // 0.2 LINK
    }

    function initialize(string memory _name, 
                string memory _uri,
                address _paymentCollection,
                uint256 _paymentTokenId,
                uint256 _price,
                address _owner
                ) public onlyFactory {
        
        boxName = _name;
        boxUri  = _uri;
        paymentCollection = IERC1155(_paymentCollection);
        paymentTokenId = _paymentTokenId;
        playOncePrice = _price;
        itemsPerSpin = 1;

        owner = _owner;
        paymentAddress = _owner;
        _staffAccountSet.add(_owner);

         _salt = uint256(keccak256(abi.encodePacked(_paymentCollection, _paymentTokenId, block.timestamp))).mod(10000);
    }

    /**
     * @dev Add tokens which have been minted, and your owned cards
     * @param tokenId. Card id you want to add.
     * @param amount. How many cards you want to add.
     */
    function addToken(address collection, uint256 tokenId, uint256 amount) public onlyStaff unbanned {
        require(IAlturaNFT(collection).balanceOf(msg.sender, tokenId) >= amount, "You don't have enough Tokens");
        IAlturaNFT(collection).safeTransferFrom(msg.sender, address(this), tokenId, amount, "Add Card");
        
        bytes32 key = itemKeyFromId(collection, tokenId);
        _cards[key].collectionId = collection;
        _cards[key].tokenId = tokenId;
        
        if(amountWithId[key] == 0) {
            _cardIndices.add(key);
        }
        
        amountWithId[key] = amountWithId[key].add(amount);
        for (uint256 i = 0; i < amount; i ++) {
            _prizePool[cardAmount + i] = key;
        }
        cardAmount = cardAmount.add(amount);
        emit AddToken(key, collection, tokenId, amount, cardAmount);
    }

    function addTokenBatch(address[] memory collections, uint256[] memory tokenIds, uint256[] memory amounts) public onlyStaff unbanned {
        require(tokenIds.length > 0 && tokenIds.length == amounts.length, 'Invalid Token ids');
        
        bytes32[] memory keys = new bytes32[](tokenIds.length);
        for(uint256 i = 0 ; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = amounts[i];
            address collection = collections[i];

            IAlturaNFT(collection).safeTransferFrom(msg.sender, address(this), tokenId, amount, "Add Cards");

            keys[i] = itemKeyFromId(collection, tokenId);
            _cards[keys[i]].collectionId = collection;
            _cards[keys[i]].tokenId = tokenId;
            
            if(amountWithId[keys[i]] == 0) {
                _cardIndices.add(keys[i]);
            }
            
            amountWithId[keys[i]] = amountWithId[keys[i]].add(amount);
            for (uint256 j = 0; j < amount; j++) {
                _prizePool[cardAmount + j] = keys[i];
            }
            cardAmount = cardAmount.add(amount);
        }

        emit AddTokenBatch(keys, collections, tokenIds, amounts, cardAmount);
    }

    /**
        Spin Lootbox with seed and times
     */
    function spin(uint256 userProvidedSeed, uint256 times) public onlyHuman unbanned {
        require(!maintaining, "This lootbox is under maintenance");
        require(!banned, "This lootbox is banned.");
        require(cardAmount > 0, "There is no card in this lootbox anymore.");
        require(times > 0, "Times can not be 0");
        require(times <= 20, "Over times.");
        require(times <= cardAmount, "You play too many times.");

        _createARound(times);

        // get random seed with userProvidedSeed and address of sender.
        uint256 seed = uint256(keccak256(abi.encode(userProvidedSeed, msg.sender)));
        
        // request random number to ChainLInk
        bytes32 requestId = _getRandomNumber(seed);
        _vrfRequests[requestId] = msg.sender;
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        address player = _vrfRequests[requestId];
        Round storage round = gameRounds[player];
        if(round.status != RoundStatus.Pending) {
            return;
        }

        if (cardAmount > shuffleCount) {
            _shufflePrizePool(randomness.mod(cardAmount));
        }

        uint256 times = round.times;
        for (uint256 i = 0; i < times; i++) {
            // get randomResult with randomness and i.
            uint256 randomResult = uint256(keccak256(abi.encode(randomness, i))).mod(cardAmount);
            // update random salt.
            _salt = ((randomResult + cardAmount + _salt) * (i + 1) * block.timestamp).mod(cardAmount) + 1;
            // transfer the cards.
            uint256 result = (randomResult * _salt).mod(cardAmount);
            _updateRound(player, result, i);
        }

        totalRoundCount = totalRoundCount.add(times);
        uint256 playFee = playOncePrice.mul(times);
        _transferToken(player, playFee);
        _distributePrize(player);

        emit SpinLootbox(player, times, playFee);
    }

    /**
     * @param amount how much token will be needed and will be burned.
     */
    function _transferToken(address player, uint256 amount) private {
        paymentCollection.safeTransferFrom(player, paymentAddress, paymentTokenId, amount, "Pay for spinning");
    }


    function _distributePrize(address player) private {
        for (uint i = 0; i < gameRounds[player].times.mul(itemsPerSpin); i ++) {
            bytes32 cardKey = gameRounds[player].cards[i];
            require(amountWithId[cardKey] > 0, "No enough cards of this kind in the lootbox.");

            Card memory card = _cards[cardKey];
            IAlturaNFT(card.collectionId).safeTransferFrom(address(this), player, card.tokenId, 1, 'Your prize from Altura Lootbox');

            amountWithId[cardKey] = amountWithId[cardKey].sub(1);
            if(amountWithId[cardKey] == 0) {
                _cardIndices.remove(cardKey);
            }
        }
        gameRounds[player].status = RoundStatus.Finished;
        gameRounds[player].lastUpdated = block.timestamp;
    }

    function _updateRound(address player, uint256 randomResult, uint256 rand) private {
        bytes32 cardKey = _prizePool[randomResult];
        _prizePool[randomResult] = _prizePool[cardAmount - 1];
        cardAmount = cardAmount.sub(1);
        gameRounds[player].cards[rand] = cardKey;
    }

    /** 
     * Requests randomness from a user-provided seed
     */
    function _getRandomNumber(uint256 seed) private returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= vrfFee, "Not enough LINK ");
        return requestRandomness(vrfKeyHash, vrfFee, seed);
    }

    function _getRandomNumebr(uint256 seed, uint256 salt, uint256 mod) view private returns(uint256) {
        return uint256(keccak256(abi.encode(block.timestamp, block.difficulty, block.coinbase, block.gaslimit, seed, block.number))).mod(mod).add(seed).add(salt);
    }

    function _createARound(uint256 times) private {
        if(gameRounds[msg.sender].status == RoundStatus.Pending 
            && block.timestamp.sub(gameRounds[msg.sender].lastUpdated) >= 10 * 60) {
            gameRounds[msg.sender].status = RoundStatus.Finished;
        }

        require(gameRounds[msg.sender].status != RoundStatus.Pending, "Currently pending now");
        gameRounds[msg.sender].id = currentRoundIdCount + 1;
        gameRounds[msg.sender].player = msg.sender;
        gameRounds[msg.sender].status = RoundStatus.Pending;
        gameRounds[msg.sender].times = times;
        gameRounds[msg.sender].totalTimes = gameRounds[msg.sender].totalTimes.add(times);
        gameRounds[msg.sender].lastUpdated = block.timestamp;
        currentRoundIdCount = currentRoundIdCount.add(1);
    }

    // shuffle the prize pool again.
    function _shufflePrizePool(uint256 randomResult) private {
        for (uint256 i = 0; i < shuffleCount; i++) {
            _salt = ((randomResult + cardAmount + _salt) * (i + 1) * block.timestamp).mod(cardAmount);
            _swapPrize(i, _salt);
        }
    }

    function _swapPrize(uint256 a, uint256 b) private {
        bytes32 temp = _prizePool[a];
        _prizePool[a] = _prizePool[b];
        _prizePool[b] = temp;
    }


    function cardKeyCount() view public returns(uint256) {
        return _cardIndices.length();
    }

    function cardKeyWithIndex(uint256 index) view public returns(bytes32) {
        return _cardIndices.at(index);
    }
    

    // ***************************
    // For Admin Account ***********
    // ***************************
    function changePlayOncePrice(uint256 newPrice) public onlyOwner {
        playOncePrice = newPrice;
    }

    function changePaymentCollection(address _collection) external onlyOwner {
        paymentCollection = IERC1155(_collection);
    }

    function changePaymentTokenId(uint256 _tokenId) external onlyOwner {
        paymentTokenId = _tokenId;
    }

    function changePaymentAddress(address _receipt) external onlyOwner {
        require(_receipt != address(0x0), "Payment address cannot Zero address");
        paymentAddress = _receipt;
    }

    function unlockLootbox() public onlyOwner {   
        maintaining = false;
        emit LootboxLocked(maintaining);
    }

    function lockLootbox() public onlyOwner {
        maintaining = true;
        emit LootboxLocked(maintaining);
    }

    function addStaffAccount(address account) public onlyOwner {
        _staffAccountSet.add(account);
    }

    function removeStaffAccount(address account) public onlyOwner {
        _staffAccountSet.remove(account);
    }

    function getStaffAccount(uint256 index) view public returns(address) {
        return _staffAccountSet.at(index);
    }

    function isStaffAccount(address account) view public returns(bool) {
        return _staffAccountSet.contains(account);
    }

    function staffAccountLength() view public returns(uint256) {
        return _staffAccountSet.length();
    }

    function transferOwner(address account) public onlyOwner {
        require(account != address(0), "Ownable: new owner is zero address");
        owner = account;
    }

    function removeOwnership() public onlyOwner {
        owner = address(0x0);
    }


    function changeShuffleCount(uint256 _shuffleCount) public onlyOwner {
        shuffleCount = _shuffleCount;
    }

    function banThisLootbox() public onlyOwner {
        banned = true;
    }

    function unbanThisLootbox() public onlyOwner {
        banned = false;
    }

    function changeLootboxName(string memory name) public onlyOwner {
        boxName = name;
    }

    function changeLootboxUri(string memory _uri) public onlyOwner {
        boxUri = _uri;
    }

    function changeItemsPerSpin(uint256 _count) public onlyOwner {
        itemsPerSpin = _count;
    }

    // This is a emergency function. you should not always call this function.
    function emergencyWithdrawCard(address collectionId, uint256 tokenId, address to, uint256 amount) public onlyOwner {
        bytes32 cardKey = itemKeyFromId(collectionId, tokenId);
        Card memory card = _cards[cardKey];
        require(card.tokenId != 0 && card.collectionId != address(0x0), "Invalid Collection id and token id");
        require(amountWithId[cardKey] >= amount, "Insufficient balance");

        IAlturaNFT(card.collectionId).safeTransferFrom(address(this), to, card.tokenId, amount, "Reset Lootbox");
        cardAmount = cardAmount.sub(amount);
        amountWithId[cardKey] = amountWithId[cardKey].sub(amount);
    }

    function emergencyWithdrawAllCards() public onlyOwner {
        for(uint256 i = 0 ; i < cardKeyCount(); i++) {
            bytes32 key = cardKeyWithIndex(i);
            if(amountWithId[key] > 0) {
                Card memory card = _cards[key];
                IAlturaNFT(card.collectionId).safeTransferFrom(address(this), msg.sender, card.tokenId, amountWithId[key], "Reset Lootbox");
                cardAmount = cardAmount.sub(amountWithId[key]);
                amountWithId[key] = 0;
            }
        }
    }

    function withdrawLINK(uint256 amount) public onlyOwner {
        require(LINK.balanceOf(address(this)) > 0, 'Insufficient LINK Token balance');
        LINK.transfer(owner, amount);
    }

    function depositLINK(uint256 amount) public {
        require(LINK.balanceOf(msg.sender) > amount, 'Insufficient LINK Token balance');
        LINK.transferFrom(msg.sender, address(this), amount);
    }

    function isContract(address _addr) view private returns (bool){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function itemKeyFromId(address _collection, uint256 _token_id) public pure returns (bytes32) {
        return keccak256(abi.encode(_collection, _token_id));
    }

    // Modifiers
    modifier onlyHuman() {
        require(!isContract(address(msg.sender)) && tx.origin == msg.sender, "Only for human.");
        _;
    }

    modifier onlyFactory() {
        require(address(msg.sender) == factory, "Only for factory.");
        _;
    }

    modifier onlyOwner() {
        require(address(msg.sender) == owner,  "Only for owner.");
        _;
    }

    modifier onlyStaff() {
        require(isStaffAccount(address(msg.sender)), "Only for staff.");
        _;
    }

    modifier unbanned() {
        require(!banned, "This lootbox is banned.");
        _;
    }
}