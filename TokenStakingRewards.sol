// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.0;

// !! IMPORTANT !! The most up to date SafeMath relies on Solidity 0.8.0's new overflow protection. 
// If you use an older version of Soliditiy you MUST also use an older version of SafeMath

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";

/* TODO
* Do we need to do any nonReentrant protection on Add & Remove stake?
*/

/**
 * @title Custom Staking Contract
 * @author Nat Eliason
 */
 
/** 
 * This contract gives you a simple interface for staking a token and earning rewards over time.
 * It's based on a fixed, non-inflationary emissions schedule. Rewards must be loaded into the contract.
 * An ideal use case is rewarding LPs with platform tokens, or rewarding platform token holders with more tokens.
 */

/**
 * Ownable to give us ownership abilities
 * SafeERC20 for safeTransfer and other functions
 * ReentrancyGuard to protect from any reentrancy exploits
 * Pausable so we can pause this if something is on fire
 */
 

contract TokenStakingRewards is Ownable, ReentrancyGuard, Pausable { 
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address[] internal stakers;
  uint public totalStakedSupply; // for tracking how much is staked in total
  mapping(address => uint) internal userStakes;
  mapping(address => uint) internal userRewards;

  uint256 public lastRewardTime; // For calculating how recently rewards were issued so we update with the right amount 

  IERC20 internal stakingToken; // address of the token people can stake
  IERC20 internal rewardToken; // address of the token people will be rewarded with

  uint public dailyEmissionsRate; // How much of the rewardToken gets distributed per day
  uint public bigMultiplier = 1000000000000; // Need this for getting around floating point issues

  // -------- CONSTRUCTOR -----------------

  constructor(address _stakingToken, address _rewardToken) {
    stakingToken = IERC20(_stakingToken);
    rewardToken = IERC20(_rewardToken);
    lastRewardTime = block.timestamp; // set this to when the contract is initiated so the first harvest isn't huge! 
  }

  // ----------- EVENTS --------------------

  event RewardAdded(uint256 reward);
  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);
  event RewardsDurationUpdated(uint256 newDuration);
  event Recovered(address token, uint256 amount);

  // --------- UTILITY FUNCTIONS ------------

  function isStaker(address _address) public view returns(bool, uint) {
    for (uint256 i = 0; i < stakers.length; i++){
      if (_address == stakers[i]) {
        return (true, i);
      }
    }
    return (false, 0);
  }
  
  function addStaker(address _staker) internal whenNotPaused {
    (bool _isStaker, ) = isStaker(_staker);
    if (!_isStaker) {
      stakers.push(_staker);
    }
  }

  function removeStaker(address _staker) public {
    (bool _isStaker, uint256 i) = isStaker(_staker);
    if (_isStaker){
      stakers[i] = stakers[stakers.length - 1];
      stakers.pop();
    }
  }

  // ----------- STAKING ACTIONS ------------

  function createStake(uint _amount) external whenNotPaused {
    require(_amount > 0, "Cannot stake 0");
    totalStakedSupply = totalStakedSupply.add(_amount);
    // If they don't exist in the userStakes mapping, add them
    if (userStakes[msg.sender] == 0) addStaker(msg.sender);
    // We should update rewards + harvest their rewards if they have here before increasing their stake
    updateRewardsEveryone();
    getRewards();
    // Increment their staked amount
    userStakes[msg.sender] = userStakes[msg.sender].add(_amount);
    // Use the safe transfer function we get from SafeERC20
    stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
    // Emit the event for the staking
    emit Staked(msg.sender, _amount);
  }

  function removeStake(uint _amount) external whenNotPaused {
    require(_amount > 0, "Cannot remove 0");
    // We should harvest their rewards here before removing their stake
    // I changed this to update everyone's rewards instead of just them, but we could change it back
    updateRewardsEveryone();
    getRewards();
    // Remove the amount from the total supply
    totalStakedSupply = totalStakedSupply.sub(_amount);
    // Update their staked amount
    userStakes[msg.sender] = userStakes[msg.sender].sub(_amount);
    // If their staked amount is now 0, remove them as a stakeholder
    if (userStakes[msg.sender] == 0) removeStaker(msg.sender);
    stakingToken.safeTransfer(msg.sender, _amount);
    emit Withdrawn(msg.sender, _amount);
  }

  // ------------ REWARD ACTIONS ---------------

  // This is the area where we'll need to see how gas fees work out. If they're too high, we'll have to adjust. 
  // This is callable by anyone... because why not right? No reason to lock it off. 

  function getBigUnpaidRewardsPerToken() public view returns (uint) {
    // we need this bigMultiplier to get around floating point issues
    uint emissionsPerSecond = dailyEmissionsRate.div(86400);
    uint rewardsToDistribute = emissionsPerSecond * timeSinceLastReward();
    uint unpaidBigRewardsPerToken = ((rewardsToDistribute * bigMultiplier) / totalStakedSupply);
    return unpaidBigRewardsPerToken;
  }

  // Updates the rewards for everyone
  function updateRewardsEveryone() public nonReentrant whenNotPaused {
    // This method should work but it's slightly imperfect. 
    // The limitation is that when someone goes to withdraw their funds we either run a separate function for their remaining rewards, or they have to run this for everyone
    uint unpaidRewardsPerToken = getBigUnpaidRewardsPerToken();
    // Update the lastRewardTime to now to avoid any double counting
    lastRewardTime = block.timestamp;

    // Now run through all the stakers and update their earned amount
    for (uint i = 0; i < stakers.length; i++) {
      address staker = stakers[i];
      uint stakerTokens = userStakes[staker];
      uint reward = stakerTokens.mul(unpaidRewardsPerToken) / bigMultiplier;
      userRewards[staker] = userRewards[staker].add(reward);
    }
  }

  // This is an alternative version we can run when someone goes to withdraw their tokens, catching up their latest rewards without having to update everyone.
  // Should save on gas for individuals and lets us have a separate master update function
  function updateIndividualRewards(address _address) internal whenNotPaused {
    uint unpaidRewardsPerToken = getBigUnpaidRewardsPerToken();
    uint stakerTokens = userStakes[_address];
    uint reward = stakerTokens.mul(unpaidRewardsPerToken) / bigMultiplier;
    userRewards[_address] = userRewards[_address].add(reward);
  }

  // This one is for someone to get their own rewards, should we let people harvest & send others rewards too? Might be useful
  function getRewards() public nonReentrant whenNotPaused {
    uint rewards = userRewards[msg.sender];
    if (rewards > 0) {
      userRewards[msg.sender] = 0;
      rewardToken.safeTransfer(msg.sender, rewards);
      emit RewardPaid(msg.sender, rewards); 
    }
  }

  // ------------ ADMIN ACTIONS ---------------

  function withdrawRewards(uint _amount) external onlyOwner {
    rewardToken.safeTransfer(msg.sender, _amount); // how do I check how much of this token is in the contract?
  }

  function depositRewards(uint _amount) external onlyOwner {
    rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
  }
  
  function setDailyEmissions(uint _amount) external onlyOwner {
    dailyEmissionsRate = _amount;
  }

  // ------------ VIEW FUNCTIONS ---------------

  function timeSinceLastReward() public view returns (uint) {
    return block.timestamp.sub(lastRewardTime);
  }

  function rewardsBalance() external view returns (uint) {
    return rewardToken.balanceOf(address(this));
  }
  
  function myRewardsBalance() external view returns (uint) {
    return userRewards[msg.sender];
  }
  
  function myStakedBalance() external view returns (uint) {
    return userStakes[msg.sender];
  }
  
  function showStakingToken() external view returns (address) {
      return address(stakingToken);
  }
  
  function showRewardToken() external view returns (address) {
      return address(rewardToken);
  }
}