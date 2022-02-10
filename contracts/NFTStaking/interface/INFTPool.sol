// Altura - NFTPool contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;


interface INFTPool {
	/** Events */
    event Deposit(address indexed user, uint256[] ids, uint256[] amounts);
    event Withdraw(address indexed user, uint256[] ids, uint256[] amounts);


    function initialize(
        string memory _name, 
        address _collection, 
        address _erc20, 
        uint256 _rewardPerBlock, 
        bool _is1155
    ) external;

    function setRewardPerBlock(uint256 _reward) external;
    function updatePool() external;

    function deposit(uint256[] calldata _ids, uint256[] calldata _amounts) external;
    function withdraw(uint256[] memory _ids, uint256[] memory _amounts) external;
    function exit() external;

    function pendingReward(address _user) external view returns (uint256);

    function userStakedNFTs(address _account) external view returns(uint256[] memory ids, uint256[] memory amounts);
    function getUserInfo(address _account) external view returns(uint256, uint256, uint256[] memory, uint256[] memory);

    function nftIdAt(uint256 holdingsIndex) external view returns (uint256);
    function allHoldings() external view returns (uint256[] memory);
    function totalHoldings() external view returns (uint256);

    function allBlockedIds() external view returns(uint256[] memory);
    function isBlockedId(uint256 _id) external view returns(bool);
}