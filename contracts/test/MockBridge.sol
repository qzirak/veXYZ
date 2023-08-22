// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../VoteEscrow.sol";

contract MockBridge {
  VoteEscrow public ve;

  constructor(VoteEscrow _ve) {
    ve = _ve;
  }

  function mint(address _to, uint256 _tokenId, bytes memory _metadata) public {
    ve.mint(_to, _tokenId, _metadata);
  }

  function burn(uint256 _tokenId) public returns (bytes memory _metadata) {
    return ve.burn(_tokenId);
  }
}
