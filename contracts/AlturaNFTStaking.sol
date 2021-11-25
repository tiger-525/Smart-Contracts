// Altura - Staking contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

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

contract AlturaNFTStaking is ERC1155Holder, Ownable  {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;


    /**
        NFTInfo Struct
     */
    struct NFTInfo {
        address collection;   // collection address
        uint256 id;        // token id of collection
    }


    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many NFT items the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        mapping(bytes32 => uint256) stakedNFTs;
        EnumerableSet.Bytes32Set nftIndices;
        //
        // We do some fancy math here. Basically, any point in time, the amount of ALUs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accALUPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accALUPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 rewardsToken;
        uint256 allocPoint;       // How many allocation points assigned to this pool. ALUs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that ALUs distribution occurs.
        uint256 accALUPerShare; // Accumulated ALUs per share,
        uint256 totalStaked;
    }
    

    // The ALU TOKEN!
    IERC20 public alu;

    address public rewardsWallet;

    // All NFT Info
    mapping(bytes32 => NFTInfo) private _nfts;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Allowed NFTs 
    mapping (uint256 => mapping(bytes32 => bool)) public allowedNFTs;      // Allowed NFT Keys
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) private userInfo;

    // The block number when ALU mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, address collection, uint256 id, uint256 amount);
    event DepositBatch(address indexed user, uint256 indexed pid, address[] collections, uint256[] ids, uint256[] amounts);
    event Withdraw(address indexed user, uint256 indexed pid, address collection, uint256 id, uint256 amount);
    event WithdrawBatch(address indexed user, uint256 indexed pid, address[] collections, uint256[] ids, uint256[] amounts);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IERC20 _alu,
        address _rewardsWallet,
        uint256 _startBlock
    ) {
        alu = _alu;
        rewardsWallet = _rewardsWallet;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            rewardsToken: _alu,
            allocPoint: 1 * 1e18,
            lastRewardBlock: startBlock,
            accALUPerShare: 0,
            totalStaked: 0
        }));

    }

    function updateRewardsWallet(address _wallet) public onlyOwner {
        require(_wallet != address(0x0), "invalid rewards wallet address");
        rewardsWallet = _wallet;
    }


    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _rewardsToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo.push(PoolInfo({
            rewardsToken: _rewardsToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accALUPerShare: 0,
            totalStaked: 0
        }));
    }

    // Update the given pool's ALU allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending ALUs on frontend.
    function pendingALU(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accALUPerShare = pool.accALUPerShare;
        uint256 totalStaked = pool.totalStaked;
        if (block.number > pool.lastRewardBlock && totalStaked != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 aluReward = multiplier.mul(pool.allocPoint);
            accALUPerShare = accALUPerShare.add(aluReward.div(totalStaked));
        }
        return user.amount.mul(accALUPerShare).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 totalStaked = pool.totalStaked;
        if (totalStaked == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 aluReward = multiplier.mul(pool.allocPoint);
        pool.accALUPerShare = pool.accALUPerShare.add(aluReward.div(totalStaked));
        pool.lastRewardBlock = block.number;
    }

    // Deposit NFT items tokens to contract for ALU allocation.
    function deposit(uint256 _pid, address _collection, uint256 _id, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accALUPerShare).sub(user.rewardDebt);
            if(pending > 0) {
                safeRewardTransfer(_pid, msg.sender, pending);
            }
        }   

        bytes32 key = itemKeyFromId(_collection, _id);
        require(allowedNFTs[_pid][key], "not allowed item");

        addNFTInfo(_collection, _id);

        if (_amount > 0) {
            IAlturaNFT(_collection).safeTransferFrom(msg.sender, address(this), _id, _amount, "deposit to AlturaNFTStaking");
            
            user.stakedNFTs[key] = user.stakedNFTs[key].add(_amount);
            user.nftIndices.add(key);
            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accALUPerShare);

        pool.totalStaked = pool.totalStaked.add(_amount);
        emit Deposit(msg.sender, _pid, _collection, _id, _amount);
    }


    function depositBatch(uint256 _pid, address[] memory _collections, uint256[] memory _ids, uint256[] memory _amounts) public {
        require (_ids.length > 0
            && _ids.length == _collections.length 
            && _ids.length == _amounts.length, "length mismatch");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accALUPerShare).sub(user.rewardDebt);
            if(pending > 0) {
                safeRewardTransfer(_pid, msg.sender, pending);
            }
        }

        uint256 totalAmount = 0;
        for (uint i = 0 ; i < _amounts.length; i++) {
            bytes32 key = itemKeyFromId(_collections[i], _ids[i]);
            require(allowedNFTs[_pid][key], "not allowed items");

            addNFTInfo(_collections[i], _ids[i]);

            IAlturaNFT(_collections[i]).safeTransferFrom(msg.sender, address(this), _ids[i], _amounts[i], "deposit to AlturaNFTStaking");

            user.stakedNFTs[key] = user.stakedNFTs[key].add(_amounts[i]);
            user.nftIndices.add(key);
            totalAmount = totalAmount.add(_amounts[i]);
        }

        if (totalAmount > 0) {
            user.amount = user.amount.add(totalAmount);
        }

        user.rewardDebt = user.amount.mul(pool.accALUPerShare);

        pool.totalStaked = pool.totalStaked.add(totalAmount);
        emit DepositBatch(msg.sender, _pid, _collections, _ids, _amounts);
    }

    // Withdraw NFT items.
    function withdraw(uint256 _pid, address _collection, uint256 _id, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        bytes32 key = itemKeyFromId(_collection, _id);
        require(user.stakedNFTs[key] >= _amount, "withdraw: too many items");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accALUPerShare).sub(user.rewardDebt);
        if(pending > 0) {
            safeRewardTransfer(_pid, msg.sender, pending);
        }

        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            user.stakedNFTs[key] = user.stakedNFTs[key].sub(_amount);
            if(user.stakedNFTs[key] == 0) {
                user.nftIndices.remove(key);
            }
            IAlturaNFT(_collection).safeTransferFrom(address(this), msg.sender, _id, _amount, "withdraw from AlturaNFTStaking");
        }

        user.rewardDebt = user.amount.mul(pool.accALUPerShare);
        pool.totalStaked = pool.totalStaked.sub(_amount);

        emit Withdraw(msg.sender, _pid, _collection, _id, _amount);
    }

    function withdrawBatch(uint256 _pid, address[] memory _collections, uint256[] memory _ids, uint256[] memory _amounts) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require (_ids.length > 0
            && _ids.length == _collections.length 
            && _ids.length == _amounts.length, "length mismatch");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accALUPerShare).sub(user.rewardDebt);
        if(pending > 0) {
            safeRewardTransfer(_pid, msg.sender, pending);
        }
        
        uint256 totalAmount = 0;
        for(uint i = 0 ; i < _ids.length; i++) {
            if(_amounts[i] > 0) {
                bytes32 key = itemKeyFromId(_collections[i], _ids[i]);
                require(user.stakedNFTs[key] >= _amounts[i], "withdraw: too many items");

                totalAmount = totalAmount.add(_amounts[i]);
                user.stakedNFTs[key] = user.stakedNFTs[key].sub(_amounts[i]);
                if(user.stakedNFTs[key] == 0) {
                    user.nftIndices.remove(key);
                }
                
                IAlturaNFT(_collections[i]).safeTransferFrom(address(this), msg.sender, _ids[i], _amounts[i], "withdraw from AlturaNFTStaking");
            }
        }
        if(totalAmount > 0) {
            user.amount = user.amount.sub(totalAmount);
            pool.totalStaked = pool.totalStaked.sub(totalAmount);
        }

        user.rewardDebt = user.amount.mul(pool.accALUPerShare);
        
        emit WithdrawBatch(msg.sender, _pid, _collections, _ids, _amounts);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function exit(uint256 _pid) public {
        UserInfo storage user = userInfo[_pid][msg.sender];

        (address[] memory collections, uint256[] memory ids, uint256[] memory amounts) 
            = getUserStakedNFTs(_pid, msg.sender);

        withdrawBatch(_pid, collections, ids, amounts);

        user.amount = 0;
        user.rewardDebt = 0;
    }


    function safeRewardTransfer(uint256 _pid, address _to, uint256 _amount) internal {
        PoolInfo memory pool = poolInfo[_pid];
        pool.rewardsToken.safeTransferFrom(rewardsWallet, _to, _amount);
    }

    function addNFTInfo(address _collection, uint256 _id) internal {
        bytes32 key = itemKeyFromId(_collection, _id);
        _nfts[key].collection = _collection;
        _nfts[key].id = _id;
    }

    function itemKeyFromId(address _collection, uint256 _token_id) public pure returns (bytes32) {
        return keccak256(abi.encode(_collection, _token_id));
    }


    function getUserInfo(uint256 _pid, address _account) public view returns(uint256, uint256) {
        UserInfo storage user = userInfo[_pid][_account];
        return (
            user.amount,
            user.rewardDebt
        );
    }
    
    function getUserStakedNFTs(uint256 _pid, address _account) 
        public 
        view 
        returns(address[] memory collections, uint256[] memory ids, uint256[] memory amounts) 
    {
        UserInfo storage user = userInfo[_pid][_account];
        uint256 totalCount = user.nftIndices.length();

        collections = new address[](totalCount);
        ids = new uint256[](totalCount);
        amounts = new uint256[](totalCount);

        for(uint i = 0 ; i < totalCount; i++) {
            bytes32 key = user.nftIndices.at(i);
            NFTInfo memory nft = _nfts[key];
            collections[i] = nft.collection;
            ids[i] = nft.id;
            amounts[i] = user.stakedNFTs[key];
        }
    }

}