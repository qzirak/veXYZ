// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IBribe.sol";
import "./interfaces/IGauge.sol";

interface IRewarder {
  function onReward(address user, address recipient, uint256 userBalance) external;
}

abstract contract Gauge is ReentrancyGuardUpgradeable, OwnableUpgradeable, IGauge {
  using SafeERC20 for IERC20;

  bool public emergency;

  IERC20 public rewardToken;

  // used in the inheriting contracts
  address public target;

  // TODO unused?
  address public ve;
  address public distribution;
  address public gaugeRewarder;
  address public internal_bribe;
  address public external_bribe;

  uint256 public duration;
  uint256 internal _periodFinish;
  uint256 public rewardRate;
  uint256 public lastUpdateTime;
  uint256 public rewardPerTokenStored;

  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public rewards;

  uint256 internal _totalSupply;
  mapping(address => uint256) internal _balances;

  event RewardAdded(uint256 reward);
  event Deposit(address indexed user, uint256 amount);
  event Withdraw(address indexed user, uint256 amount);
  event Harvest(address indexed user, uint256 reward);

  event ClaimFees(address indexed from, uint256 fees);
  event EmergencyActivated(address indexed gauge, uint256 timestamp);
  event EmergencyDeactivated(address indexed gauge, uint256 timestamp);

  modifier updateReward(address account) {
    rewardPerTokenStored = rewardPerToken();
    lastUpdateTime = lastTimeRewardApplicable();
    if (account != address(0)) {
      rewards[account] = earned(account);
      userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
    _;
  }

  modifier onlyDistribution() {
    require(msg.sender == distribution, "Caller is not RewardsDistribution contract");
    _;
  }

  modifier isNotEmergency() {
    require(emergency == false, "emergency");
    _;
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _rewardToken,
    address _ve,
    address _target,
    address _distribution,
    address _internal_bribe,
    address _external_bribe
  ) external initializer {
    __Ownable_init();
    __ReentrancyGuard_init();

    rewardToken = IERC20(_rewardToken); // main reward
    ve = _ve; // vested
    target = _target; // gauge target address
    distribution = _distribution; // distro address (voter)
    duration = 14 days; // distro time

    internal_bribe = _internal_bribe; // lp fees goes here
    external_bribe = _external_bribe; // bribe fees goes here

    emergency = false; // emergency flag
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  ///@notice set distribution address (should be voter)
  function setDistribution(address _distribution) external onlyOwner {
    require(_distribution != address(0), "zero addr");
    require(_distribution != distribution, "same addr");
    distribution = _distribution;
  }

  ///@notice set gauge rewarder address
  function setGaugeRewarder(address _gaugeRewarder) external onlyOwner {
    require(_gaugeRewarder != gaugeRewarder, "same addr");
    gaugeRewarder = _gaugeRewarder;
  }

  ///@notice set new internal bribe contract (where to send fees)
  function setInternalBribe(address _int) external onlyOwner {
    require(_int >= address(0), "zero");
    internal_bribe = _int;
  }

  function activateEmergencyMode() external onlyOwner {
    require(emergency == false, "emergency");
    emergency = true;
    emit EmergencyActivated(address(this), block.timestamp);
  }

  function stopEmergencyMode() external onlyOwner {
    require(emergency == true, "emergency");

    emergency = false;
    emit EmergencyDeactivated(address(this), block.timestamp);
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VIEW FUNCTIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  ///@notice total supply held
  function totalSupply() public view returns (uint256) {
    return _totalSupply;
  }

  ///@notice balance of a user
  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  ///@notice last time reward
  function lastTimeRewardApplicable() public view returns (uint256) {
    // return min
    return block.timestamp < _periodFinish ? block.timestamp : _periodFinish;
  }

  ///@notice  reward for a sinle token
  function rewardPerToken() public view returns (uint256) {
    if (_totalSupply == 0) {
      return rewardPerTokenStored;
    } else {
      return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply;
    }
  }

  ///@notice see earned rewards for user
  function earned(address account) public view returns (uint256) {
    return rewards[account] + (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18;
  }

  ///@notice get total reward for the duration
  function rewardForDuration() external view returns (uint256) {
    return rewardRate * duration;
  }

  function periodFinish() external view returns (uint256) {
    return _periodFinish;
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    USER INTERACTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  ///@notice User harvest function called from distribution (voter allows harvest on multiple gauges)
  function getReward(address _user) public nonReentrant onlyDistribution updateReward(_user) {
    uint256 reward = rewards[_user];
    if (reward > 0) {
      rewards[_user] = 0;
      rewardToken.safeTransfer(_user, reward);
      emit Harvest(_user, reward);
    }

    if (gaugeRewarder != address(0)) {
      IRewarder(gaugeRewarder).onReward(_user, _user, _balances[_user]);
    }
  }

  ///@notice User harvest function
  function getReward() public nonReentrant updateReward(msg.sender) {
    uint256 reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      rewardToken.safeTransfer(msg.sender, reward);
      emit Harvest(msg.sender, reward);
    }

    if (gaugeRewarder != address(0)) {
      IRewarder(gaugeRewarder).onReward(msg.sender, msg.sender, _balances[msg.sender]);
    }
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  /// @dev Receive rewards from distribution

  function notifyRewardAmount(
    address token,
    uint256 reward
  ) external nonReentrant isNotEmergency onlyDistribution updateReward(address(0)) {
    require(token == address(rewardToken), "not rew token");
    rewardToken.safeTransferFrom(distribution, address(this), reward);

    if (block.timestamp >= _periodFinish) {
      rewardRate = reward / duration;
    } else {
      uint256 remaining = _periodFinish - block.timestamp;
      uint256 leftover = remaining * rewardRate;
      rewardRate = (reward + leftover) / duration;
    }

    // Ensure the provided reward amount is not more than the balance in the contract.
    // This keeps the reward rate in the right range, preventing overflows due to
    // very high values of rewardRate in the earned and rewardsPerToken functions;
    // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
    uint256 balance = rewardToken.balanceOf(address(this));
    require(rewardRate <= balance / duration, "Provided reward too high");

    lastUpdateTime = block.timestamp;
    _periodFinish = block.timestamp + duration;
    emit RewardAdded(reward);
  }

  function _claimFees() internal virtual returns (bytes memory);
}
