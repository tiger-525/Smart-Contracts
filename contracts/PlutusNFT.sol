// Plutus NFT token
// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract PlutusNFT is ERC1155, AccessControl {
	using SafeMath for uint256;
	
	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
	uint256 constant public PERCENTS_DIVIDER = 1000;

	constructor() public ERC1155("https://plutus-app-mvp.herokuapp.com/api/item/") {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(MINTER_ROLE, msg.sender);
	}

	uint256 public items;

	event ItemAdded(uint256 id, uint256 maxSupply, uint256 supply);

	mapping(uint256 => address) private _creators;
	mapping(uint256 => uint256) private _creatorFee;  
	mapping(uint256 => uint256) public totalSupply;
	mapping(uint256 => uint256) public circulatingSupply;


	function addItem(uint256 maxSupply, uint256 supply, uint256 _fee) public returns (uint256) {
		require(maxSupply > 0, "Maximum supply can not be 0");
		require(supply <= maxSupply, "Supply can not be greater than Maximum supply");
		require(_fee < PERCENTS_DIVIDER, "Too big creator fee");
		
		items = items.add(1);
		totalSupply[items] = maxSupply;
		circulatingSupply[items] = maxSupply;

		_creators[items] = msg.sender;
		_creatorFee[items] = _fee;

		if(supply > 0) {
			_mint(msg.sender, items, supply, "");
		}

		emit ItemAdded(items, maxSupply, supply);
		return items;
	}

	function setURI(string memory newuri) public  {
		require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 'only for admin');

        _setURI(newuri);
    }

	function mint(address to, uint256 id, uint256 amount) public returns (bool){
		require(hasRole(MINTER_ROLE, msg.sender) || creatorOf(id) == msg.sender, "Only minter or creator can mint");
		require(circulatingSupply[id].add(amount) <= totalSupply[id], "Total supply reached.");

		circulatingSupply[id] = circulatingSupply[id].add(amount);
		_mint(to, id, amount, "");
		return true;
	}
		
	function burn(address from, uint256 id, uint256 amount) public returns(bool){
		require(hasRole(MINTER_ROLE, msg.sender) || creatorOf(id) == msg.sender, "Only minter or creator can burn");

		circulatingSupply[id] = circulatingSupply[id].sub(amount);
		_burn(from, id, amount);
		return true;
	}

	
  	function creatorOf(uint256 id) public view returns (address) {
        return _creators[id];
	}

	function creatorFee(uint256 id) public view returns (uint256) {
        return _creatorFee[id];
	}
}