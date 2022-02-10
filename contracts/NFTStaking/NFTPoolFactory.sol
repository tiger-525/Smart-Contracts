// Altura - NFT Staking Factory contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interface/INFTPoolFactory.sol";
import "./NFTPool.sol";

contract NFTPoolFactory is INFTPoolFactory, UUPSUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

	address[] internal pools;

    EnumerableSet.AddressSet private _blockedCollections;
    EnumerableSet.AddressSet private _blockedTokens;

	function initialize() public initializer {
		__Ownable_init();
        __INFTPoolFactory_init();
    }

    function __INFTPoolFactory_init() public override initializer {

    }

	function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


	function createPool(string memory _name, address _collection, address _erc20, uint _reward, bool _is1155) external virtual override returns(address _pool) {
        require(!_blockedCollections.contains(_collection), "blocked collection");
        require(isContract(_collection), "invalid collection contract");
        require(!_blockedTokens.contains(_erc20), "blocked token address");
        require(_erc20 == address(0x0) || isContract(_erc20), "invalid reward token contract");

		bytes memory bytecode = type(NFTPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_name, block.timestamp));
        assembly {
            _pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        NFTPool(_pool).initialize(_name, _collection, _erc20, _reward, _is1155);
		pools.push(_pool);

		emit PoolCreated(_pool, msg.sender, _name, _collection, _erc20, _reward, _is1155);
	}

    function blockCollection(address _collection) external virtual override onlyOwner {
		_blockedCollections.add(_collection);
	}

    function blockToken(address _erc20) external virtual override onlyOwner {
		_blockedTokens.add(_erc20);
	}

    function allPools() external view virtual override returns (address[] memory) {
        return pools;
    }

    function pool(uint256 poolId) external view virtual override returns (address) {
        return pools[poolId];
    }

    function numPools() external view virtual override returns (uint256) {
        return pools.length;
    }

    function isContract(address _addr) view private returns (bool){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}