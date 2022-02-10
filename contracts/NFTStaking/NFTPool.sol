// Altura - NFT Pool contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./interface/INFTPool.sol";
import "./interface/INFTPoolFactory.sol";


contract NFTPool is INFTPool, ERC1155Holder, ERC721Holder, Ownable  {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    string public name;
    address public collection;
    address public rewardToken;
    uint256 public rewardPerBlock;
    uint256 private lastRewardBlock;  // Last block number that rewards token distribution occurs.
    uint256 private accRewardPerShare; // Accumulated rewards per share,
    uint256 public totalStaked;

    bool public is1155;
    
    INFTPoolFactory public factory;
    uint256 public poolId;


    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many NFT items the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        EnumerableSet.UintSet nftIndices;
    }

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _stakedTokens;

    EnumerableSet.UintSet holdings;
    mapping(uint256 => uint256) quantity1155;
    
    // blocked NFTs 
    EnumerableSet.UintSet private _blockedNFTs;      // Blocked NFT Ids

    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) private userInfo;

    // The block number when Reward mining starts.
    uint256 public startBlock;
    
    constructor() {
		factory = INFTPoolFactory(msg.sender);
	}

    function initialize(
        string memory _name, 
        address _collection, 
        address _erc20, 
        uint256 _rewardPerBlock, 
        bool _is1155
    ) public virtual override onlyFactory {
        name = _name;
        collection = _collection;
        rewardToken = _erc20;
        rewardPerBlock = _rewardPerBlock;
        is1155 = _is1155;
        startBlock = block.number;

        poolId = factory.numPools();
    }

    function version() external pure returns (string memory) {
        return "v1.0.0";
    } 

    // Update the given pool's reward per block. Can only be called by the owner.
    function setRewardPerBlock(uint256 _reward) external virtual override onlyOwner {
        updatePool();
        
        rewardPerBlock = _reward;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending Rewards on frontend.
    function pendingReward(address _user) external view virtual override returns (uint256)  {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.number > lastRewardBlock && totalStaked != 0) {
            uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
            uint256 rewardAmount = multiplier.mul(rewardPerBlock);
            _accRewardPerShare = _accRewardPerShare.add(rewardAmount.div(totalStaked));
        }
        return user.amount.mul(_accRewardPerShare).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public virtual override {
        if (block.number <= lastRewardBlock) {
            return;
        }
        
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 rewardAmount = multiplier.mul(rewardPerBlock);
        accRewardPerShare = accRewardPerShare.add(rewardAmount.div(totalStaked));
        lastRewardBlock = block.number;
    }

    // Deposit NFT items tokens to contract.
    function deposit(uint256[] calldata _ids, uint256[] calldata _amounts) external virtual override {
        UserInfo storage user = userInfo[msg.sender];

        updatePool();
        
        // if pending of User, transfer
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accRewardPerShare).sub(user.rewardDebt);
            if(pending > 0) {
                safeRewardTransfer(msg.sender, pending);
            }
        }   

        uint256 totalReceived = safeReceiveNFTs(msg.sender, _ids, _amounts);
        
        for (uint i = 0 ; i < _ids.length; i++) {
            uint256 _id = _ids[i];
            user.nftIndices.add(_id);
            _stakedTokens[msg.sender][_id] += _amounts[i];
        }

        if(totalReceived > 0) {
            user.amount = user.amount.add(totalReceived);
            user.rewardDebt = user.amount.mul(accRewardPerShare);

            totalStaked = totalStaked.add(totalReceived);
        }
        
        emit Deposit(msg.sender, _ids, _amounts);
    }

    function withdraw(uint256[] memory _ids, uint256[] memory _amounts) public virtual override {
        UserInfo storage user = userInfo[msg.sender];

        require (_ids.length > 0
            && _ids.length == _amounts.length, "length mismatch");

        updatePool();

        uint256 pending = user.amount.mul(accRewardPerShare).sub(user.rewardDebt);
        if(pending > 0) {
            safeRewardTransfer(msg.sender, pending);
        }
        
        uint256 totalWithdrawn = safeWithdrawNFTs(msg.sender, _ids, _amounts);

        for(uint i = 0 ; i < _ids.length; i++) {
            uint256 _id = _ids[i];
            uint256 _amount = _amounts[i];

            if(_amount > 0) {
                require(_stakedTokens[msg.sender][_id] >= _amount, "withdraw: too many items");

                _stakedTokens[msg.sender][_id] = _stakedTokens[msg.sender][_id].sub(_amount);
                if(_stakedTokens[msg.sender][_id] == 0) {
                    user.nftIndices.remove(_id);
                }
            }
        }
        if(totalWithdrawn > 0) {
            user.amount = user.amount.sub(totalWithdrawn);
            user.rewardDebt = user.amount.mul(accRewardPerShare);
            totalStaked = totalStaked.sub(totalWithdrawn);
        }

        emit Withdraw(msg.sender, _ids, _amounts);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function exit() external virtual override {
        UserInfo storage user = userInfo[msg.sender];

        (uint256[] memory ids, uint256[] memory amounts) = userStakedNFTs(msg.sender);

        withdraw(ids, amounts);

        user.amount = 0;
        user.rewardDebt = 0;
    }

    function safeReceiveNFTs(address _from, uint256[] memory _ids, uint256[] memory _amounts) internal returns (uint256){
        uint256 length = _ids.length;
        
        if(is1155) {
            require(length == _amounts.length, "length mismatch");
            IERC1155(collection).safeBatchTransferFrom(
                _from,
                address(this),
                _ids,
                _amounts,
                ""
            );

            uint256 count;
            for (uint256 i; i < length; ++i) {
                uint256 tokenId = _ids[i];
                uint256 amount = _amounts[i];
                 
                require(_blockedNFTs.contains(tokenId), "not allowed item");
                require(amount != 0, "transferring < 1");
                if (quantity1155[tokenId] == 0) {
                    holdings.add(tokenId);
                }
                quantity1155[tokenId] += amount;
                count += amount;
            }
            return count;
        } else {
            for (uint256 i; i < length; ++i) {
                uint256 tokenId = _ids[i];
                require(_blockedNFTs.contains(tokenId), "not allowed item");
                IERC721(collection).safeTransferFrom(_from, address(this), tokenId);
                holdings.add(tokenId);
            }
            return length;
        }
    }

    function safeWithdrawNFTs(address _to, uint256[] memory _ids, uint256[] memory _amounts) internal returns (uint256){
        uint256 length = _ids.length;
        
        if(is1155) {
            require(length == _amounts.length, "length mismatch");
            IERC1155(collection).safeBatchTransferFrom(
                address(this),
                _to,
                _ids,
                _amounts,
                ""
            );

            uint256 count;
            for (uint256 i; i < length; ++i) {
                uint256 tokenId = _ids[i];
                uint256 amount = _amounts[i];
                require(amount != 0, "transferring < 1");
                quantity1155[tokenId] -= amount;
                if (quantity1155[tokenId] == 0) {
                    holdings.remove(tokenId);
                }
                count += amount;
            }
            return count;
        } else {
            for (uint256 i; i < length; ++i) {
                uint256 tokenId = _ids[i];
                IERC721(collection).safeTransferFrom(address(this), _to, tokenId);
                holdings.remove(tokenId);
            }
            return length;
        }
    }


    function safeRewardTransfer(address _to, uint256 _amount) internal {
        IERC20(rewardToken).safeTransfer(_to, _amount);
    }

    function getUserInfo(address _account) external view override returns(uint256, uint256, uint256[] memory, uint256[] memory) {
        UserInfo storage user = userInfo[_account];
        (uint256[] memory ids, uint256[] memory amounts) = userStakedNFTs(msg.sender);
        return (
            user.amount,
            user.rewardDebt,
            ids,
            amounts
        );
    }
    
    function userStakedNFTs(address _account) public view override returns(uint256[] memory ids, uint256[] memory amounts) 
    {
        UserInfo storage user = userInfo[_account];
        uint256 totalCount = user.nftIndices.length();

        ids = new uint256[](totalCount);
        amounts = new uint256[](totalCount);

        for(uint i = 0 ; i < totalCount; i++) {
            uint id = user.nftIndices.at(i);
            ids[i] = id;
            amounts[i] = _stakedTokens[_account][id];
        }
    }

    function nftIdAt(uint256 holdingsIndex) external view override virtual returns (uint256) {
        return holdings.at(holdingsIndex);
    }

    function allHoldings() external view override virtual returns (uint256[] memory) {
        return holdings.values();
    }

    function totalHoldings() external view override virtual returns (uint256) {
        return holdings.length();
    }

    function allBlockedIds() external view override virtual returns(uint256[] memory) {
        return _blockedNFTs.values();
    }

    function isBlockedId(uint256 _id) external view override virtual returns(bool) {
        return _blockedNFTs.contains(_id);
    }

    modifier onlyFactory() {
        require(address(factory) == _msgSender(), "caller is not the factory");
        _;
    }

    modifier onlyManager() {
        require(address(factory) == _msgSender() || owner() == _msgSender(), "caller is not the manager");
        _;
    }

}