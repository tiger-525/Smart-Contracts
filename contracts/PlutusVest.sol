// Plutus - Vest contract
// SPDX-License-Identifier: MIT 

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./DateTimeLibrary.sol";

interface IBEP20 {
  function totalSupply() external view returns (uint256);
  function decimals() external view returns (uint8);
  function symbol() external view returns (string memory);
  function name() external view returns (string memory);
  function getOwner() external view returns (address);
  function balanceOf(address account) external view returns (uint256);

  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address _owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract PlutusVest is Ownable {
    using SafeMath for uint256;
	using DateTimeLibrary for uint;

	uint256 constant public TOTAL_SUPPLY = 1e27;
	uint256 constant public DAYS_PER_MONTH = 30; 

    IBEP20 public plutusToken;

    /* Vest Items */
	struct Vest {
		string name;
		uint256 allocation;
		address receiver;
		uint256 lockDuration;        // lock duration : month
		uint256 totalDuration;
		uint256 lastReleased;
		uint256 totalReleased;
		bool bValid;
	} 

	Vest[] public vests;
	mapping(string => uint256) public vestIndices;

	uint public startTime;
    
   
	/** Events */
    event Released(string name, uint256 amount, address receiver);


    constructor(address _plutus, address _team1, address _team2, address _marketing, address _operation, address _reserve, uint _start) public {
		startTime = _start;
		
		plutusToken = IBEP20(_plutus);

		vests.push(Vest("Team1",       TOTAL_SUPPLY.mul(1).div(100),   _team1,        3, 13,  _start.sub(1),  0,  true )); vestIndices["Team1"]     = 0;
		vests.push(Vest("Team2",       TOTAL_SUPPLY.mul(9).div(100),   _team2,        3, 13,  _start.sub(1),  0,  true )); vestIndices["Team2"]     = 1;
		vests.push(Vest("Marketing",   TOTAL_SUPPLY.mul(10).div(100),  _marketing,    3, 13,  _start.sub(1),  0,  true )); vestIndices["Marketing"] = 2;
		vests.push(Vest("Operation",   TOTAL_SUPPLY.mul(15).div(100),  _operation,    1, 11,  _start.sub(1),  0,  true )); vestIndices["Operation"] = 3;
		vests.push(Vest("Reserve",     TOTAL_SUPPLY.mul(10).div(100),  _reserve,      3, 13,  _start.sub(1),  0,  true )); vestIndices["Reserve"]   = 4;
    }

    function setAddress(string calldata name, address _address) external onlyOwner {
        require(_address != address(0x0), "invalid address");

		vests[vestIndices[name]].receiver = _address;
    }

	function setPlutusAddress(address _address) external onlyOwner {
        require(_address != address(0x0), "invalid address");

		plutusToken = IBEP20(_address);
    }

	function release() public onlyOwner {
		for(uint i = 0 ; i < vests.length; i++) {
			Vest storage v = vests[i];
			
			uint lockEnd = DateTimeLibrary.addMonths(startTime, v.lockDuration);
			// check locked status
			if(block.timestamp <= lockEnd) {
				continue;
			} else if(v.totalReleased >= v.allocation) {
				continue;
			} else {
				uint passDays = DateTimeLibrary.diffDays(lockEnd, block.timestamp);
				uint256 months = uint256(passDays).div(DAYS_PER_MONTH).add(1);
				uint256 available = (v.allocation.div(v.totalDuration - v.lockDuration).mul(months)).sub(v.totalReleased);

				if(available > 0) {
					if(plutusToken.transfer(v.receiver, available)) {
						v.totalReleased = v.totalReleased.add(available);
						v.lastReleased = block.timestamp;

						emit Released(v.name, available, v.receiver);
					}
				}
			}
		}
	}

	function plutusBalance() view public returns(uint256){
		return plutusToken.balanceOf(address(this));
	}

	function emergencyWithdraw() public onlyOwner {
		plutusToken.transfer(msg.sender, plutusBalance());
	}
}