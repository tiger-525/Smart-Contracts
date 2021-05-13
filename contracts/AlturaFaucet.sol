// Altura - Faucet contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract AlturaFaucet is Ownable {
	using SafeMath for uint256;

    uint256 constant public SECONDS_PER_DAY = 24 * 3600;

    IERC20 public alturaToken;
    uint256 public amountPerDay;
    mapping(address => uint256) public lastClaimed;

    bool public faucetStopped = false;
    uint256 public totalFunds = 0;

    event Faucet(address account, uint256 amount);


    constructor(address _token) public {
		alturaToken = IERC20(_token);

        amountPerDay = 1000 * 10 ** 18;
	}

    function setToken(address _token) public onlyOwner {
        alturaToken = IERC20(_token);
    }

    function setAmountPerDay(uint256 _amount) public onlyOwner {
        amountPerDay = _amount;
    }

    function setFaucetStopped(bool _stopped) public onlyOwner {
        faucetStopped = _stopped;
    }

    function remainSeconds(address account) public view returns(uint256) {
        if(lastClaimed[account] == 0) {
            return 0;
        }else if(lastClaimed[account].add(SECONDS_PER_DAY) <= block.timestamp) {
            return 0;
        }else {
            return lastClaimed[account].add(SECONDS_PER_DAY).sub(block.timestamp);
        }
    }

    function claim() external notStopped {
        require(remainSeconds(msg.sender) == 0, "Can claim only once everyday");
        require(alturaToken.transfer(msg.sender, amountPerDay), "Failed to transfer");

        lastClaimed[msg.sender] = block.timestamp;
        totalFunds = totalFunds.add(amountPerDay);

        emit Faucet(msg.sender, amountPerDay);
    }

    modifier notStopped() {
        require(faucetStopped == false, "faucet stopped");
        _;
    }
}