// Altura - NFT Swap contract
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
	function mint(address to, uint256 id, uint256 amount) external returns(bool);
	function balanceOf(address account, uint256 id) external view returns (uint256);
	function creatorOf(uint256 id) external view returns (address);
	function royaltyOf(uint256 id) external view returns (uint256);
}

contract AlturaNFTFactory is UUPSUpgradeable, ERC1155HolderUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;

	uint256 constant public PERCENTS_DIVIDER = 1000;
	uint256 constant public FEE_MAX_PERCENT = 300;
	uint256 constant public DEFAULT_FEE_PERCENT = 40;
	
	address constant public wethAddress = 0x094616F0BdFB0b526bD735Bf66Eca0Ad254ca81F;  // BSC Testnet
	//address constant public wethAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;    // BSC Mainnet

    /* Pairs to swap NFT _id => price */
	struct Item {
		uint256 item_id;
		address collection;
		uint256 token_id;
		address creator;
		address owner;
		uint256 balance;
		address currency;
		uint256 price;
		uint256 royalty;
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

	mapping(address => uint256) public swapFees; // swap fees (currency => fee) : percent divider = 1000
	address public feeAddress; 


	/** Events */
    event CollectionCreated(address collection_address, address owner, string name, string uri, bool isPublic);
    event ItemListed(uint256 id, address collection, uint256 token_id, uint256 amount, uint256 price, address currency, address creator, address owner, uint256 royalty);
	event ItemDelisted(uint256 id);
	event ItemPriceUpdated(uint256 id, uint256 price, address currency);
	event ItemAdded(uint256 id, uint256 amount, uint256 balance);
	event ItemRemoved(uint256 id, uint256 amount, uint256 balance);

    event Swapped(address buyer, uint256 id, uint256 amount);

	function initialize(address _fee) public initializer {
		__Ownable_init();
		__ERC1155Holder_init();
		__ReentrancyGuard_init();

        feeAddress = _fee;
		swapFees[address(0x0)] = 40;
		swapFees[0xFdb09FBeb34A5b00473382d47fD718da889B7Feb] = 25;   //Alutra Token

		createCollection("AlturaNFT", "https://api.alturanft.com/meta/alturanft/", true);
    }

	function _authorizeUpgrade(address newImplementation) internal override {}

	function setFeeAddress(address _address) external onlyOwner {
		require(_address != address(0x0), "invalid address");
        feeAddress = _address;
    }

	function setSwapFeePercent(address currency,uint256 _percent) external onlyOwner {
		require(_percent < FEE_MAX_PERCENT, "too big swap fee");
		swapFees[currency] = _percent;
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

    function list(address _collection, uint256 _token_id, uint256 _amount, uint256 _price, address _currency, bool _bMint) public {
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
		items[currentItemId].owner = msg.sender;
		items[currentItemId].balance = _amount;
		items[currentItemId].price = _price;
		items[currentItemId].currency = _currency;
		items[currentItemId].bValid = true;

		try nft.creatorOf(_token_id) returns (address creator) {
            items[currentItemId].creator = creator;
			items[currentItemId].royalty = nft.royaltyOf(_token_id);
        } catch (bytes memory /*lowLevelData*/) {
           
        }

        emit ItemListed(currentItemId, 
			_collection,
			_token_id, 
			_amount, 
			_price, 
			_currency,
			items[currentItemId].creator,
			msg.sender,
			items[currentItemId].royalty
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
    
	function updatePrice(uint256 _id, address _currency, uint256 _price) external {
		require(_price > 0, "invalid new price");
		require(items[_id].bValid, "invalid Item id");
		require(items[_id].owner == msg.sender || msg.sender == owner(), "only owner can update price");

		items[_id].price = _price;
		items[_id].currency = _currency;

		emit ItemPriceUpdated(_id, _price, _currency);
	}

    function buy(uint256 _id, uint256 _amount) external payable nonReentrant {
        require(items[_id].bValid, "invalid Item id");
		require(items[_id].balance >= _amount, "insufficient NFT balance");
		require(items[_id].currency != address(0x0) || items[_id].price.mul(_amount) == msg.value, "Invalid amount");

		Item memory item = items[_id];
		uint256 swapFee = swapFees[item.currency];
		if(swapFee == 0x0) {
			swapFee = DEFAULT_FEE_PERCENT;
		}
		uint256 plutusAmount = item.price.mul(_amount);
		uint256 ownerPercent = PERCENTS_DIVIDER.sub(swapFee).sub(item.royalty);

		// transfer Plutus token to admin
		if(item.currency == address(0x0)) {
			if(swapFee > 0) {
				require(_safeTransferBNB(feeAddress, plutusAmount.mul(swapFee).div(PERCENTS_DIVIDER)), "failed to transfer admin fee");
			}
			// transfer Plutus token to creator
			if(item.royalty > 0) {
				require(_safeTransferBNB(item.creator, plutusAmount.mul(item.royalty).div(PERCENTS_DIVIDER)), "failed to transfer creator fee");
			}
			// transfer Plutus token to owner
			require(_safeTransferBNB(item.owner, plutusAmount.mul(ownerPercent).div(PERCENTS_DIVIDER)), "failed to transfer to owner");
		}else {
			if(swapFee > 0) {
				require(IERC20(item.currency).transferFrom(msg.sender, feeAddress, plutusAmount.mul(swapFee).div(PERCENTS_DIVIDER)), "failed to transfer admin fee");
			}
			// transfer Plutus token to creator
			if(item.royalty > 0) {
				require(IERC20(item.currency).transferFrom(msg.sender, item.creator, plutusAmount.mul(item.royalty).div(PERCENTS_DIVIDER)), "failed to transfer creator fee");
			}
			// transfer Plutus token to owner
			require(IERC20(item.currency).transferFrom(msg.sender, item.owner, plutusAmount.mul(ownerPercent).div(PERCENTS_DIVIDER)), "failed to transfer to owner");
		}

		// transfer NFT token to buyer
		IAlturaNFT(items[_id].collection).safeTransferFrom(address(this), msg.sender, item.token_id, _amount, "buy from Altura Marketplace");

		items[_id].balance = items[_id].balance.sub(_amount);
		items[_id].totalSold = items[_id].totalSold.add(_amount);

		totalSold = totalSold.add(_amount);
		totalEarning = totalEarning.add(plutusAmount);
		totalSwapped = totalSwapped.add(1);

        emit Swapped(msg.sender, _id, _amount);
    }

	function _safeTransferBNB(address to, uint256 value) internal returns(bool) {
		(bool success, ) = to.call{value: value}(new bytes(0));
		if(!success) {
			IWETH(wethAddress).deposit{value: value}();
			return IERC20(wethAddress).transfer(to, value);
		}
		return success;
        
    }
	
	receive() external payable {}
}