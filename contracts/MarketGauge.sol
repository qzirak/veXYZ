// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/IMarket.sol";
import "./Gauge.sol";

contract MarketGauge is Gauge {
  function claimFees() external {
    claimMarketFees();
  }

  function claimMarketFees() public nonReentrant returns (uint256) {
    return abi.decode(_claimFees(), (uint256));
  }

  function _claimFees() internal override returns (bytes memory) {
    uint256 fees = IMarket(target).totalAdminFees();

    if (fees > 0) {
      IMarket(target)._withdrawAdminFees(fees);
      address underlying = IMarket(target).underlying();

      if (fees > 0) {
        // assuming that the admin is the gauge
        IERC20(underlying).approve(internal_bribe, fees);
        IBribe(internal_bribe).notifyRewardAmount(underlying, fees);
      }
      emit ClaimFees(msg.sender, fees);
    }

    return abi.encode(fees);
  }
}
