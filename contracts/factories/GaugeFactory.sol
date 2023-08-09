// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../VoterRolesAuthority.sol";
import "../interfaces/IGaugeFactory.sol";
import "../MarketGauge.sol";

// TODO SafeOwnableUpgradeable?
contract GaugeFactory is IGaugeFactory, OwnableUpgradeable {
  address public last_gauge;
  VoterRolesAuthority public permissionsRegistry;

  address[] internal _gauges;
  Gauge public gaugeLogic;

  constructor() {
    _disableInitializers();
  }

  function initialize(VoterRolesAuthority _permissionRegistry) public initializer {
    __Ownable_init();
    permissionsRegistry = _permissionRegistry;
    gaugeLogic = new MarketGauge();
  }

  function reinitialize() public reinitializer(1) {
    gaugeLogic = new MarketGauge();
  }

  function setRegistry(VoterRolesAuthority _registry) external {
    require(owner() == msg.sender, "not owner");
    permissionsRegistry = _registry;
  }

  function gauges() external view returns (address[] memory) {
    return _gauges;
  }

  function length() external view returns (uint) {
    return _gauges.length;
  }

  struct AddressSlot {
    address value;
  }

  function _getProxyAdmin() internal view returns (address admin) {
    bytes32 _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    AddressSlot storage adminSlot;
    assembly {
      adminSlot.slot := _ADMIN_SLOT
    }
    admin = adminSlot.value;
  }

  function createGauge(
    address _rewardToken,
    address _ve,
    address _token,
    address _distribution,
    address _internal_bribe,
    address _external_bribe
  ) external returns (address) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(gaugeLogic), _getProxyAdmin(), "");
    Gauge(address(proxy)).initialize(_rewardToken, _ve, _token, _distribution, _internal_bribe, _external_bribe);
    last_gauge = address(proxy);
    _gauges.push(last_gauge);
    return last_gauge;
  }

  modifier onlyAllowed() {
    require(
      owner() == msg.sender || permissionsRegistry.canCall(msg.sender, address(this), msg.sig),
      "ERR: GAUGE_ADMIN"
    );
    _;
  }

  modifier EmergencyCouncil() {
    require(permissionsRegistry.canCall(msg.sender, address(this), msg.sig), "ERR: EMERGENCY COUNCIL");
    _;
  }

  function activateEmergencyMode() external EmergencyCouncil {
    uint i = 0;
    for (i; i < _gauges.length; i++) {
      IGauge(_gauges[i]).activateEmergencyMode();
    }
  }

  function stopEmergencyMode() external EmergencyCouncil {
    uint i = 0;
    for (i; i < _gauges.length; i++) {
      IGauge(_gauges[i]).stopEmergencyMode();
    }
  }

  function setGaugeRewarder(address[] memory _rewarder) external onlyAllowed {
    require(_gauges.length == _rewarder.length);
    uint i = 0;
    for (i; i < _gauges.length; i++) {
      IGauge(_gauges[i]).setGaugeRewarder(_rewarder[i]);
    }
  }

  function setDistribution(address distro) external onlyAllowed {
    uint i = 0;
    for (i; i < _gauges.length; i++) {
      IGauge(_gauges[i]).setDistribution(distro);
    }
  }

  function setInternalBribe(address[] memory int_bribe) external onlyAllowed {
    require(_gauges.length == int_bribe.length);
    uint i = 0;
    for (i; i < _gauges.length; i++) {
      IGauge(_gauges[i]).setInternalBribe(int_bribe[i]);
    }
  }
}
