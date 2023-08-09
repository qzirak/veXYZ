// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGaugeFactory {
  function createGauge(
    address _rewardToken,
    address _ve,
    address _target,
    address _distribution,
    address _internal_bribe,
    address _external_bribe
  ) external returns (address);
}
