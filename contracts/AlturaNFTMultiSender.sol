// Altura NFT token Multi sender
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract AlturaNFTMultiSender is ERC1155Holder {
	using SafeMath for uint256;
	
	constructor() {
	}
	
	/**
		Multi sender
	 */
	function multiSend(address[] memory to, address collection, uint256 id, uint256 amount) public {
		require(to.length > 0, "invalid to address");
		
		for(uint i = 0; i < to.length; i++) {
			IERC1155(collection).safeTransferFrom(msg.sender, to[i], id, amount, "multi send");
		}
	}	

	receive() external payable {revert();}
}