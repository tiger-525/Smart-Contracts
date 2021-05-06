// Altura - NFT Swap contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IAlturaNFT {
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

	uint256 constant public PERCENTS_DIVIDER = 1000;

    IERC20 public alturaToken;
    IAlturaNFT public alturaNFT;

    /* Pairs to swap NFT _id => price */
	struct Item {
		uint256 item_id;
		uint256 token_id;
		address creator;
		address owner;
		uint256 balance;
		uint256 price;
		uint256 creatorFee;
		uint256 totalSold;
		bool bValid;
	}

    mapping(uint256 => Item) public items;
	uint256 public currentItemId;
    
    uint256 public totalSold;  /* Total NFT token amount sold */
	uint256 public totalEarning; /* Total Plutus Token */
	uint256 public totalSwapped; /* Total swap count */


	uint256 public swapFee;  // swap fee as percent - percent divider = 1000
	address public feeAddress; 


	/** Events */
    event ItemListed(uint256 id, uint256 token_id, uint256 amount, uint256 price, address creator, address owner, uint256 creatorFee);
	event ItemDelisted(uint256 id);
	event ItemAdded(uint256 id, uint256 amount);

    event Swapped(address buyer, uint256 id, uint256 amount);

	function initialize(address _altura, address _nft, address _fee) public initializer {
		__Ownable_init();
		__ERC1155Holder_init();

        alturaToken = IERC20(_altura);
        alturaNFT   = IAlturaNFT(_nft);
		feeAddress = _fee;
		swapFee = 20; // 2%
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
		require(_percent < PERCENTS_DIVIDER, "too big swap fee");
		swapFee = _percent;
	}

    function list(uint256 _token_id, uint256 _amount, uint256 _price, bool _bMint) public {
		require(_price > 0, "invalid price");
		require(_amount > 0, "invalid amount");

		if(_bMint) {
			require(msg.sender == alturaNFT.creatorOf(_token_id), "only creator can mint");
			require(alturaNFT.mint(address(this), _token_id, _amount), "mint failed");
		} else {
			require(alturaNFT.balanceOf(msg.sender, _token_id) >= _amount, "insufficient balance");
			alturaNFT.safeTransferFrom(msg.sender, address(this), _token_id, _amount, "List");
		}

		currentItemId = currentItemId.add(1);
		items[currentItemId].item_id = currentItemId;
		items[currentItemId].token_id = _token_id;
		items[currentItemId].creator = alturaNFT.creatorOf(_token_id);
		items[currentItemId].owner = msg.sender;
		items[currentItemId].balance = _amount;
		items[currentItemId].price = _price;
		items[currentItemId].creatorFee = alturaNFT.creatorFee(_token_id);
		items[currentItemId].totalSold = 0;
		items[currentItemId].bValid = true;

        emit ItemListed(currentItemId, 
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

		alturaNFT.safeTransferFrom(address(this), items[_id].owner, items[_id].token_id, items[_id].balance, "delist from Altura Marketplace");
		items[_id].balance = 0;
		items[_id].bValid = false;

		emit ItemDelisted(_id);
	}

	function addItems(uint256 _id, uint256 _amount) external {
		require(items[_id].bValid, "invalid Item id");
		require(items[_id].owner == msg.sender, "only owner can add items");

		alturaNFT.safeTransferFrom(msg.sender, address(this), items[_id].token_id, _amount, "add items to Altura Marketplace");
		items[_id].balance = items[_id].balance.add(_amount);

		emit ItemAdded(_id, _amount);
	}
    
    function buy(uint256 _id, uint256 _amount) external {
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
		alturaNFT.safeTransferFrom(address(this), msg.sender, item.token_id, _amount, "buy from Altura Marketplace");

		items[_id].balance = items[_id].balance.sub(_amount);
		items[_id].totalSold = items[_id].totalSold.add(_amount);

		totalSold = totalSold.add(_amount);
		totalEarning = totalEarning.add(plutusAmount);
		totalSwapped = totalSwapped.add(1);

        emit Swapped(msg.sender, _id, _amount);
    }
}