// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { RolesAuthority, Authority } from "solmate/auth/authorities/RolesAuthority.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract VoterRolesAuthority is RolesAuthority, Initializable {
  constructor() RolesAuthority(address(0), Authority(address(0))) {
    _disableInitializers();
  }

  function initialize(address _owner) public initializer {
    owner = _owner;
    authority = this;
  }
}
