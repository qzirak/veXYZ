// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/IMinter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract EpochsTimer is IMinter, Initializable {
  uint public active_period;
  uint public constant TWO_WEEKS = 2 weeks;

  function initialize() external initializer {
    // empty
  }

  function update_period() external returns (uint256) {
    uint _period = active_period;
    if (block.timestamp >= _period + TWO_WEEKS) {
      _period = (block.timestamp / TWO_WEEKS) * TWO_WEEKS;
      active_period = _period;
    }
    return _period;
  }

  function check() external view returns (bool) {
    uint _period = active_period;
    return (block.timestamp >= _period + TWO_WEEKS);
  }

  function period() external view returns (uint256) {
    return (block.timestamp / TWO_WEEKS) * TWO_WEEKS;
  }
}
