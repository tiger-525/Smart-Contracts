// Altura - NFT Swap contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./AlturaNFT.sol";

interface IAlturaNFT {
	function initialize(string memory _name, string memory _uri, address creator, bool bPublic) external;
	function safeTransferFrom(address from,
			address to,
			uint256 id,
			uint256 amount,
			bytes calldata data) external;
	function mint(address to, uint256 id, uint256 amount) external returns(bool);
	function balanceOf(address account, uint256 id) external view returns (uint256);
	function creatorOf(uint256 id) external view returns (address);
	function creatorFee(uint256 id) external view returns (uint256);
}

contract AlturaNFTSwap is UUPSUpgradeable, ERC1155HolderUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;

	uint256 constant public PERCENTS_DIVIDER = 1000;
	uint256 constant public FEE_MAX_PERCENT = 300;
	

    IERC20 public alturaToken;
    IAlturaNFT public alturaNFT;

    /* Pairs to swap NFT _id => price */
	struct Item {
		uint256 item_id;
		address collection;
		uint256 token_id;
		address creator;
		address owner;
		uint256 balance;
		uint256 price;
		uint256 creatorFee;
		uint256 totalSold;
		bool bValid;
	}

	address[] public collections;
	// collection address => creator address
	mapping(address => address) public collectionCreators;
	// token id => Item mapping
    mapping(uint256 => Item) public items;
	uint256 public currentItemId;
    
    uint256 public totalSold;  /* Total NFT token amount sold */
	uint256 public totalEarning; /* Total Plutus Token */
	uint256 public totalSwapped; /* Total swap count */


	uint256 public swapFee;  // swap fee as percent - percent divider = 1000
	address public feeAddress; 


	/** Events */
    event CollectionCreated(address collection_address, address owner, string name, string uri, bool isPublic);
    event ItemListed(uint256 id, address collection, uint256 token_id, uint256 amount, uint256 price, address creator, address owner, uint256 creatorFee);
	event ItemDelisted(uint256 id);
	event ItemPriceUpdated(uint256 id, uint256 price);
	event ItemAdded(uint256 id, uint256 amount, uint256 balance);
	event ItemRemoved(uint256 id, uint256 amount, uint256 balance);

    event Swapped(address buyer, uint256 id, uint256 amount);

	function initialize(address _altura, address _fee) public initializer {
		__Ownable_init();
		__ERC1155Holder_init();

        alturaToken = IERC20(_altura);
        feeAddress = _fee;
		swapFee = 25; // 2.5%

		address _default_nft = createCollection("AlturaNFT", "https://plutus-app-mvp.herokuapp.com/api/item/", true);
		alturaNFT = IAlturaNFT(_default_nft);
    }

	function _authorizeUpgrade(address newImplementation) internal override {}

    function setalturaToken(address _address) external onlyOwner {
        require(_address != address(0x0), "invalid address");
		alturaToken = IERC20(_address);
    }

    function setNFTAddress(address _address) external onlyOwner {
		require(_address != address(0x0), "invalid address");
        alturaNFT = IAlturaNFT(_address);
    }

	function setFeeAddress(address _address) external onlyOwner {
		require(_address != address(0x0), "invalid address");
        feeAddress = _address;
    }

	function setSwapFeePercent(uint256 _percent) external onlyOwner {
		require(_percent < FEE_MAX_PERCENT, "too big swap fee");
		swapFee = _percent;
	}

	function createCollection(string memory _name, string memory _uri, bool bPublic) public returns(address collection) {
		bytes memory bytecode = type(AlturaNFT).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_uri, _name, block.timestamp));
        assembly {
            collection := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IAlturaNFT(collection).initialize(_name, _uri, msg.sender, bPublic);
		collections.push(collection);
		collectionCreators[collection] = msg.sender;

		emit CollectionCreated(collection, msg.sender, _name, _uri, bPublic);
	}

    function list(address _collection, uint256 _token_id, uint256 _amount, uint256 _price, bool _bMint) public {
		require(_price > 0, "invalid price");
		require(_amount > 0, "invalid amount");

		IAlturaNFT nft = IAlturaNFT(_collection);
		if(_bMint) {
			require(nft.mint(address(this), _token_id, _amount), "mint failed");
		} else {
			nft.safeTransferFrom(msg.sender, address(this), _token_id, _amount, "List");
		}

		currentItemId = currentItemId.add(1);
		items[currentItemId].item_id = currentItemId;
		items[currentItemId].collection = _collection;
		items[currentItemId].token_id = _token_id;
		items[currentItemId].creator = nft.creatorOf(_token_id);
		items[currentItemId].owner = msg.sender;
		items[currentItemId].balance = _amount;
		items[currentItemId].price = _price;
		items[currentItemId].creatorFee = nft.creatorFee(_token_id);
		items[currentItemId].totalSold = 0;
		items[currentItemId].bValid = true;

        emit ItemListed(currentItemId, 
			_collection,
			_token_id, 
			_amount, 
			_price, 
			items[currentItemId].creator,
			msg.sender,
			items[currentItemId].creatorFee
		);
    }

	function delist(uint256 _id) external {
		require(items[_id].bValid, "invalid Item id");
		require(items[_id].owner == msg.sender || msg.sender == owner(), "only owner can delist");

		IAlturaNFT(items[_id].collection).safeTransferFrom(address(this), items[_id].owner, items[_id].token_id, items[_id].balance, "delist from Altura Marketplace");
		items[_id].balance = 0;
		items[_id].bValid = false;

		emit ItemDelisted(_id);
	}

	function addItems(uint256 _id, uint256 _amount) external {
		require(items[_id].bValid, "invalid Item id");
		require(items[_id].owner == msg.sender, "only owner can add items");

		IAlturaNFT(items[_id].collection).safeTransferFrom(msg.sender, address(this), items[_id].token_id, _amount, "add items to Altura Marketplace");
		items[_id].balance = items[_id].balance.add(_amount);

		emit ItemAdded(_id, _amount, items[_id].balance);
	}

	function removeItems(uint256 _id, uint256 _amount) external {
		require(items[_id].bValid, "invalid Item id");
		require(items[_id].owner == msg.sender, "only owner can remove items");
		
		IAlturaNFT(items[_id].collection).safeTransferFrom(address(this), msg.sender, items[_id].token_id, _amount, "remove items from Altura Marketplace");
		items[_id].balance = items[_id].balance.sub(_amount, "insufficient balance of item");

		emit ItemRemoved(_id, _amount, items[_id].balance);
	}
    
	function updatePrice(uint256 _id, uint256 _price) external {
		require(_price > 0, "invalid new price");
		require(items[_id].bValid, "invalid Item id");
		require(items[_id].owner == msg.sender || msg.sender == owner(), "only owner can update price");

		items[_id].price = _price;

		emit ItemPriceUpdated(_id, _price);
	}

	function buy(uint256 _id, uint256 _amount) external {
		_buy(_id, _amount);
	}
	
	function batchBuy(uint256[] memory _ids, uint256[] memory _amounts) external {
		require(_ids.length == _amounts.length, "ids and amounts length mismatch");

		for (uint256 i = 0; i < _ids.length; ++i) {
			_buy(_ids[i], _amounts[i]);
        }
	}

    function _buy(uint256 _id, uint256 _amount) internal {
        require(items[_id].bValid, "invalid Item id");
		require(items[_id].balance >= _amount, "insufficient NFT balance");

		Item memory item = items[_id];
		uint256 plutusAmount = item.price.mul(_amount);

		// transfer Plutus token to admin
		if(swapFee > 0) {
			require(alturaToken.transferFrom(msg.sender, feeAddress, plutusAmount.mul(swapFee).div(PERCENTS_DIVIDER)), "failed to transfer admin fee");
		}
		// transfer Plutus token to creator
		if(item.creatorFee > 0) {
			require(alturaToken.transferFrom(msg.sender, item.creator, plutusAmount.mul(item.creatorFee).div(PERCENTS_DIVIDER)), "failed to transfer creator fee");
		}
		// transfer Plutus token to owner
		uint256 ownerPercent = PERCENTS_DIVIDER.sub(swapFee).sub(item.creatorFee);
		require(alturaToken.transferFrom(msg.sender, item.owner, plutusAmount.mul(ownerPercent).div(PERCENTS_DIVIDER)), "failed to transfer to owner");

		// transfer NFT token to buyer
		IAlturaNFT(items[_id].collection).safeTransferFrom(address(this), msg.sender, item.token_id, _amount, "buy from Altura Marketplace");

		items[_id].balance = items[_id].balance.sub(_amount);
		items[_id].totalSold = items[_id].totalSold.add(_amount);

		totalSold = totalSold.add(_amount);
		totalEarning = totalEarning.add(plutusAmount);
		totalSwapped = totalSwapped.add(1);

        emit Swapped(msg.sender, _id, _amount);
    }
}