// Altura - NFT Staking Factory contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;


interface INFTPoolFactory {
	/** Events */
    event PoolCreated(address indexed pool, address indexed owner, string name, address collection, address erc20, uint reward, bool is1155);


    function __INFTPoolFactory_init() external;
	function createPool(string memory _name, address _collection, address _erc20, uint _reward, bool _is1155) external returns(address);

    function blockCollection(address _collection) external;
    function blockToken(address _erc20) external;

    function allPools() external view returns (address[] memory);
    function pool(uint256 poolId) external view returns (address);
    function numPools() external view returns (uint256);
}