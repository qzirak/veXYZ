// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBribe {
  function getRewardForOwner(uint tokenId, address[] memory tokens) external;

  function getRewardForAddress(address _owner, address[] memory tokens) external;

  function notifyRewardAmount(address token, uint amount) external;
}
