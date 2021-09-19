// Altura - NFT Auction contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./AlturaNFT.sol";


interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;

    function transfer(address to, uint256 value) external returns (bool);
}

interface IAlturaNFT {
	function initialize(string memory _name, string memory _uri, address creator, bool bPublic) external;
	function safeTransferFrom(address from,
			address to,
			uint256 id,
			uint256 amount,
			bytes calldata data) external;
	function mint(address to, uint256 id, uint256 amount, bytes memory data) external returns(bool);
	function balanceOf(address account, uint256 id) external view returns (uint256);
	function creatorOf(uint256 id) external view returns (address);
	function royaltyOf(uint256 id) external view returns (uint256);
}

contract AlturaNFTAuction is UUPSUpgradeable, ERC1155HolderUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;

	uint256 constant public PERCENTS_DIVIDER = 1000;
	uint256 constant public FEE_MAX_PERCENT = 300;
	uint256 constant public DEFAULT_FEE_PERCENT = 40;
	
	//address constant public wethAddress = 0x094616F0BdFB0b526bD735Bf66Eca0Ad254ca81F;  // BSC Testnet
	address constant public wethAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;    // BSC Mainnet

	/* Auctions _id => price */
	struct Auction {
		address collectionId;
		uint256 tokenId;
		address creator;
		address owner;
		bool isUnlimitied;
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;
        address currency;
		uint256 royalty;
		bool active;
        bool finalized;
	}

	// Bid struct to hold bidder and amount
    struct Bid {
        address payable from;
		address currency;
        uint256 amount;
    }

	// auction id => Item mapping
    mapping(uint256 => Auction) public auctions;
	uint256 public currentAuctionId;

	// Mapping from auction index to user bids
    mapping (uint256 => Bid[]) public auctionBids;
    
    // Mapping from owner to a list of owned auctions
    mapping (address => uint256[]) public ownedAuctions;

    
    uint256 public totalSold;  /* Total NFT token amount sold */
	uint256 public totalEarning; /* Total Plutus Token */
	uint256 public totalSwapped; /* Total swap count */

	mapping(address => uint256) public swapFees; // swap fees (currency => fee) : percent divider = 1000
	address public feeAddress; 

	/** Events */
    event AuctionCreated(uint256 id, Auction auction);
	event AuctionCancelled(uint256 id, Auction auction);
	event AuctionFinalized(uint256, Auction auction);

	event BidSuccess(address from, uint auctionId, uint256 price, address currency, uint bidIndex);


	function initialize(address _fee) public initializer {
		__Ownable_init();
		__ERC1155Holder_init();
		__ReentrancyGuard_init();

        feeAddress = _fee;
		swapFees[address(0x0)] = 40;
		swapFees[0x8263CD1601FE73C066bf49cc09841f35348e3be0] = 25;   //Alutra Token
    }

	function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

	function setFeeAddress(address _address) external onlyOwner {
		require(_address != address(0x0), "invalid address");
        feeAddress = _address;
    }

	function setSwapFeePercent(address currency,uint256 _percent) external onlyOwner {
		require(_percent < FEE_MAX_PERCENT, "too big swap fee");
		swapFees[currency] = _percent;
	}

	

    function createAuction(
		address _collectionId, 
        uint256 _tokenId,
        address _currency, 
        uint256 _startPrice, 
        uint256 _startTime,
        uint256 _endTime,
        bool _isUnlimited
	) public onlyTokenOwner(_collectionId, _tokenId) {

		currentAuctionId = currentAuctionId.add(1);
		Auction memory newAuction;
        newAuction.collectionId = _collectionId;
        newAuction.tokenId = _tokenId;
        newAuction.startPrice = _startPrice;
        newAuction.currency = _currency;
        newAuction.startTime = _startTime;
        newAuction.endTime = _endTime;
        newAuction.isUnlimitied = _isUnlimited;
        newAuction.owner = msg.sender;
        newAuction.active = true;
        newAuction.finalized = false;
        
        auctions[currentAuctionId] = newAuction;        
        ownedAuctions[msg.sender].push(currentAuctionId);

		IAlturaNFT(_collectionId).safeTransferFrom(msg.sender, address(this), _tokenId, 1, "create auction");

        emit AuctionCreated(currentAuctionId, newAuction);
    }

	/**
     * @dev Cancels an ongoing auction by the owner
     * @dev Deed is transfered back to the auction owner
     * @dev Bidder is refunded with the initial amount
     * @param _auctionId uint ID of the created auction
     */
    function cancelAuction(uint _auctionId) public onlyAuctionOwner(_auctionId) nonReentrant {
        Auction memory myAuction = auctions[_auctionId];
        uint bidsLength = auctionBids[_auctionId].length;

        require(msg.sender == owner() || bidsLength == 0, "bid already started");

        // approve and transfer from this contract to auction owner
		IAlturaNFT(myAuction.collectionId).safeTransferFrom(address(this), myAuction.owner, myAuction.tokenId, 1, "cancel auction");

        auctions[_auctionId].active = false;
		auctions[_auctionId].finalized = true;

        emit AuctionCancelled(_auctionId, myAuction);
    }

	function _safeTransferBNB(address to, uint256 value) internal returns(bool) {
		(bool success, ) = to.call{value: value}(new bytes(0));
		if(!success) {
			IWETH(wethAddress).deposit{value: value}();
			return IERC20(wethAddress).transfer(to, value);
		}
		return success;
        
    }
	
	/**
     * @dev Gets the length of auctions
     * @return uint representing the auction count
     */
    function getAuctionsLength() public view returns(uint) {
        return currentAuctionId;
    }
    
    /**
     * @dev Gets the bid counts of a given auction
     * @param _auctionId uint ID of the auction
     */
    function getBidsAmount(uint _auctionId) public view returns(uint) {
        return auctionBids[_auctionId].length;
    } 
    
    /**
     * @dev Gets an array of owned auctions
     * @param _owner address of the auction owner
     */
    function getOwnedAuctions(address _owner) public view returns(uint[] memory) {
        uint[] memory ownedAllAuctions = ownedAuctions[_owner];
        return ownedAllAuctions;
    }
    
    /**
     * @dev Gets an array of owned auctions
     * @param _auctionId uint of the auction owner
     * @return amount uint256, address of last bidder
     */
    function getCurrentBids(uint _auctionId) public view returns(uint256, address) {
        uint bidsLength = auctionBids[_auctionId].length;
        // if there are bids refund the last bid
        if (bidsLength >= 0) {
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];
            return (lastBid.amount, lastBid.from);
        }    
        return (0, address(0));
    }
    
    /**
     * @dev Gets the total number of auctions owned by an address
     * @param _owner address of the owner
     * @return uint total number of auctions
     */
    function getAuctionsAmount(address _owner) public view returns(uint) {
        return ownedAuctions[_owner].length;
    }

    function isBNBAuction(uint _auctionId) public view returns (bool) {
        return auctions[_auctionId].currency == address(0x0);
    }

    receive() external payable {}

    modifier onlyAuctionOwner(uint _auctionId) {
        require(auctions[_auctionId].owner == msg.sender || msg.sender == owner(), "only auction owner");
        _;
    }

    modifier onlyTokenOwner(address _collectionId, uint256 _tokenId) {
        require(IAlturaNFT(_collectionId).balanceOf(msg.sender, _tokenId) > 0, "only token owner");
        _;
    }
}