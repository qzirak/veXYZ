// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMarket {
  function underlying() external view returns (address);

  function totalAdminFees() external view returns (uint256);

  function _withdrawAdminFees(uint256) external returns (uint256);

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function totalSupply() external view returns (uint);

  function decimals() external view returns (uint8);
}
