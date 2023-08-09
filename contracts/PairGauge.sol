// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/IPair.sol";
import "./Gauge.sol";

contract PairGauge is Gauge {
  function claimFees() external {
    claimPairFees();
  }

  function claimPairFees() public nonReentrant returns (uint256 claimed0, uint256 claimed1) {
    return abi.decode(_claimFees(), (uint256, uint256));
  }

  function _claimFees() internal override returns (bytes memory) {
    uint256 claimed0;
    uint256 claimed1;
    IPair pair = IPair(target);

    (claimed0, claimed1) = pair.claimFees();
    if (claimed0 > 0 || claimed1 > 0) {
      uint256 _fees0 = claimed0;
      uint256 _fees1 = claimed1;

      (address _token0, address _token1) = pair.tokens();

      if (_fees0 > 0) {
        IERC20(_token0).approve(internal_bribe, 0);
        IERC20(_token0).approve(internal_bribe, _fees0);
        IBribe(internal_bribe).notifyRewardAmount(_token0, _fees0);
      }
      if (_fees1 > 0) {
        IERC20(_token1).approve(internal_bribe, 0);
        IERC20(_token1).approve(internal_bribe, _fees1);
        IBribe(internal_bribe).notifyRewardAmount(_token1, _fees1);
      }
      emit ClaimFees(msg.sender, claimed0, claimed1);
    }

    return abi.encode(claimed0, claimed1);
  }

  event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
}
