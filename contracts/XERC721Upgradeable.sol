// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IERC721Upgradeable, IERC721MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

abstract contract XERC721Upgradeable is ERC721Upgradeable, Ownable2StepUpgradeable {
  event BridgeAdded(address indexed bridge);
  event BridgeRemoved(address indexed bridge);
  event MintAsBridge(uint _tokenId, bytes _metadata);
  event BurnAsBridge(uint _tokenId, bytes _metadata);

  mapping(address => bool) internal _whitelistedBridges;

  constructor() {}

  function __XERC721_init() internal onlyInitializing {
    __XERC721_init_unchained();
  }

  function __XERC721_init_unchained() internal onlyInitializing {}

  error XERC721__onlyBridge_notBridge();
  error XERC721__addBridge_alreadyAdded();
  error XERC721__removeBridge_alreadyRemoved();

  modifier onlyBridge() {
    if (!_whitelistedBridges[msg.sender]) {
      revert XERC721__onlyBridge_notBridge();
    }
    _;
  }

  function addBridge(address _bridge) external onlyOwner {
    if (_whitelistedBridges[_bridge]) {
      revert XERC721__addBridge_alreadyAdded();
    }
    emit BridgeAdded(_bridge);
    _whitelistedBridges[_bridge] = true;
  }

  function removeBridge(address _bridge) external onlyOwner {
    if (!_whitelistedBridges[_bridge]) {
      revert XERC721__removeBridge_alreadyRemoved();
    }
    emit BridgeRemoved(_bridge);
    _whitelistedBridges[_bridge] = false;
  }

  function mint(address _to, uint256 _tokenId, bytes memory _metadata) public onlyBridge {
    _mint(_to, _tokenId);
    _afterMint(_tokenId, _metadata);

    emit MintAsBridge(_tokenId, _metadata);
  }

  function burn(uint256 _tokenId) public onlyBridge returns (bytes memory _metadata) {
    _metadata = _beforeBurn(_tokenId);
    _burn(_tokenId);

    emit BurnAsBridge(_tokenId, _metadata);
  }

  function _afterMint(uint256 _tokenId, bytes memory _metadata) internal virtual;

  function _beforeBurn(uint256 _tokenId) internal virtual returns (bytes memory _metadata);

  uint256[49] private __GAP; // gap for upgrade safety
}
