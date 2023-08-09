// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/IBribe.sol";
import "./interfaces/IBribeFactory.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IGaugeFactory.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IMarket.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVoteEscrow.sol";
import "./VoterRolesAuthority.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract VoterV3 is IVoter, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  address public _ve; // the ve token that governs these contracts
  address public factory; // classic stable and volatile Pair Factory
  address[] public factories; // Array with all the pair factories
  address internal base; // $ion token
  address public gaugeFactory; // gauge factory
  address[] public gaugeFactories; // array with all the gauge factories
  address public bribeFactory; // bribe factory (internal and external)
  address public minter; // minter mints $ion each epoch
  VoterRolesAuthority public permissionRegistry; // registry to check accesses
  address[] public markets; // all markets viable for incentives

  uint internal index; // gauge index
  uint internal constant DURATION = 14 days; // rewards are released over 14 days
  uint public VOTE_DELAY; // delay between votes in seconds
  uint public constant MAX_VOTE_DELAY = 10 days; // Max vote delay allowed

  mapping(address => uint) internal supplyIndex; // gauge    => index
  mapping(address => uint) public claimable; // gauge    => claimable $ion
  mapping(address => address) public gauges; // market     => gauge
  mapping(address => uint) public gaugesDistributionTimestamp; // gauge    => last Distribution Time
  mapping(address => address) public marketForGauge; // gauge    => market
  mapping(address => address) public internal_bribes; // gauge    => internal bribe (only fees)
  mapping(address => address) public external_bribes; // gauge    => external bribe (real bribes)
  mapping(uint => mapping(address => uint256)) public votes; // nft      => market     => votes
  mapping(uint => address[]) public marketVote; // nft      => markets
  mapping(uint => mapping(address => uint)) internal weightsPerEpoch; // timestamp => market => weights
  mapping(uint => uint) internal totWeightsPerEpoch; // timestamp => total weights
  mapping(uint => uint) public usedWeights; // nft      => total voting weight of user
  mapping(uint => uint) public lastVoted; // nft      => timestamp of last vote
  mapping(address => bool) public isGauge; // gauge    => boolean [is a gauge?]
  mapping(address => bool) public isAlive; // gauge    => boolean [is the gauge alive?]
  mapping(address => bool) public isFactory; // factory  => boolean [the pair factory exists?]
  mapping(address => bool) public isGaugeFactory; // g.factory=> boolean [the gauge factory exists?]

  event GaugeCreated(
    address indexed gauge,
    address creator,
    address internal_bribe,
    address indexed external_bribe,
    address indexed market
  );
  event GaugeKilled(address indexed gauge);
  event GaugeRevived(address indexed gauge);
  event Voted(address indexed voter, uint tokenId, uint256 weight);
  event Abstained(uint tokenId, uint256 weight);
  event NotifyReward(address indexed sender, address indexed reward, uint amount);
  event DistributeReward(address indexed sender, address indexed gauge, uint amount);
  event Attach(address indexed owner, address indexed gauge, uint tokenId);
  event Detach(address indexed owner, address indexed gauge, uint tokenId);

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address __ve,
    address _factory,
    address _gauges,
    address _bribes,
    VoterRolesAuthority _permissionsRegistry,
    address _minter
  ) public initializer {
    __Ownable_init();
    __ReentrancyGuard_init();

    _ve = __ve;
    base = IVoteEscrow(__ve).token();

    factory = _factory;
    factories.push(factory);
    isFactory[factory] = true;

    gaugeFactory = _gauges;
    gaugeFactories.push(_gauges);
    isGaugeFactory[_gauges] = true;

    bribeFactory = _bribes;

    minter = msg.sender;
    minter = _minter;
    permissionRegistry = _permissionsRegistry;

    VOTE_DELAY = 0;
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    MODIFIERS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  modifier VoterAdmin() {
    require(permissionRegistry.canCall(msg.sender, address(this), msg.sig), "ERR: VOTER_ADMIN");
    _;
  }

  modifier Governance() {
    require(isGovernor(), "ERR: GOVERNANCE");
    _;
  }

  function isGovernor() internal view returns (bool) {
    return permissionRegistry.canCall(msg.sender, address(this), msg.sig);
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VoterAdmin
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  /// @notice set vote delay in seconds
  function setVoteDelay(uint _delay) external VoterAdmin {
    require(_delay != VOTE_DELAY);
    require(_delay <= MAX_VOTE_DELAY);
    VOTE_DELAY = _delay;
  }

  /// @notice Set a new Minter
  function setMinter(address _minter) external VoterAdmin {
    require(_minter != address(0));
    minter = _minter;
  }

  /// @notice Set a new Bribe Factory
  function setBribeFactory(address _bribeFactory) external VoterAdmin {
    bribeFactory = _bribeFactory;
  }

  /// @notice Set a new Gauge Factory
  function setGaugeFactory(address _gaugeFactory) external VoterAdmin {
    gaugeFactory = _gaugeFactory;
  }

  /// @notice Set a new Pair Factory
  function setPairFactory(address _factory) external VoterAdmin {
    factory = _factory;
  }

  /// @notice Set a new PermissionRegistry
  function setPermissionsRegistry(VoterRolesAuthority _permissionRegistry) external VoterAdmin {
    permissionRegistry = _permissionRegistry;
  }

  /// @notice Set a new bribes for a given gauge
  function setNewBribes(address _gauge, address _internal, address _external) external VoterAdmin {
    require(isGauge[_gauge] == true);
    _setInternalBribe(_gauge, _internal);
    _setExternalBribe(_gauge, _external);
  }

  /// @notice Set a new internal bribe for a given gauge
  function setInternalBribeFor(address _gauge, address _internal) external VoterAdmin {
    require(isGauge[_gauge]);
    _setInternalBribe(_gauge, _internal);
  }

  /// @notice Set a new External bribe for a given gauge
  function setExternalBribeFor(address _gauge, address _external) external VoterAdmin {
    require(isGauge[_gauge]);
    _setExternalBribe(_gauge, _external);
  }

  function _setInternalBribe(address _gauge, address _internal) private {
    internal_bribes[_gauge] = _internal;
  }

  function _setExternalBribe(address _gauge, address _external) private {
    external_bribes[_gauge] = _external;
  }

  /// @notice Increase gauge approvals if max is type(uint).max is reached    [very long run could happen]
  function increaseGaugeApprovals(address _gauge) external VoterAdmin {
    require(isGauge[_gauge]);
    IERC20(base).approve(_gauge, 0);
    IERC20(base).approve(_gauge, type(uint).max);
  }

  function addFactory(address _pairFactory, address _gaugeFactory) external VoterAdmin {
    require(_pairFactory != address(0), "addr 0");
    require(_gaugeFactory != address(0), "addr 0");
    require(!isFactory[_pairFactory], "factory true");
    require(!isGaugeFactory[_gaugeFactory], "g.fact true");

    factories.push(_pairFactory);
    gaugeFactories.push(_gaugeFactory);
    isFactory[_pairFactory] = true;
    isGaugeFactory[_gaugeFactory] = true;
  }

  function replaceFactory(address _pairFactory, address _gaugeFactory, uint256 _pos) external VoterAdmin {
    require(_pairFactory != address(0), "addr 0");
    require(_gaugeFactory != address(0), "addr 0");
    require(isFactory[_pairFactory], "factory false");
    require(isGaugeFactory[_gaugeFactory], "g.fact false");
    address oldPF = factories[_pos];
    address oldGF = gaugeFactories[_pos];
    isFactory[oldPF] = false;
    isGaugeFactory[oldGF] = false;

    factories[_pos] = (_pairFactory);
    gaugeFactories[_pos] = (_gaugeFactory);
    isFactory[_pairFactory] = true;
    isGaugeFactory[_gaugeFactory] = true;
  }

  function removeFactory(uint256 _pos) external VoterAdmin {
    address oldPF = factories[_pos];
    address oldGF = gaugeFactories[_pos];
    require(isFactory[oldPF], "factory false");
    require(isGaugeFactory[oldGF], "g.fact false");
    factories[_pos] = address(0);
    gaugeFactories[_pos] = address(0);
    isFactory[oldPF] = false;
    isGaugeFactory[oldGF] = false;
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    GOVERNANCE
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  /// @notice Kill a malicious gauge
  /// @param  _gauge gauge to kill
  function killGauge(address _gauge) external Governance {
    require(isAlive[_gauge], "gauge already dead");
    isAlive[_gauge] = false;
    claimable[_gauge] = 0;
    emit GaugeKilled(_gauge);
  }

  /// @notice Revive a malicious gauge
  /// @param  _gauge gauge to revive
  function reviveGauge(address _gauge) external Governance {
    require(!isAlive[_gauge], "gauge already alive");
    require(isGauge[_gauge], "gauge killed totally");
    isAlive[_gauge] = true;
    supplyIndex[_gauge] = index;
    emit GaugeRevived(_gauge);
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    USER INTERACTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  /// @notice Reset the votes of a given TokenID
  function reset(uint _tokenId) external nonReentrant {
    _voteDelay(_tokenId);
    require(IVoteEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
    _reset(_tokenId);
    IVoteEscrow(_ve).abstain(_tokenId);
    lastVoted[_tokenId] = _epochTimestamp() + 1;
  }

  function _reset(uint _tokenId) internal {
    address[] storage _marketVote = marketVote[_tokenId];
    uint _marketVoteCnt = _marketVote.length;
    uint256 _totalWeight = 0;
    uint256 _time = _epochTimestamp();

    for (uint i = 0; i < _marketVoteCnt; i++) {
      address _market = _marketVote[i];
      uint256 _votes = votes[_tokenId][_market];

      if (_votes != 0) {
        // if user last vote is < than epochTimestamp then votes are 0! IF not underflow occur
        if (lastVoted[_tokenId] > _epochTimestamp()) weightsPerEpoch[_time][_market] -= _votes;

        votes[_tokenId][_market] -= _votes;
        _totalWeight += _votes;

        emit Abstained(_tokenId, _votes);
      }
    }

    // if user last vote is < than epochTimestamp then _totalWeight is 0! IF not underflow occur
    if (lastVoted[_tokenId] < _epochTimestamp()) _totalWeight = 0;

    totWeightsPerEpoch[_time] -= _totalWeight;
    usedWeights[_tokenId] = 0;
    delete marketVote[_tokenId];
  }

  /// @notice Recast the saved votes of a given TokenID
  function poke(uint _tokenId) external nonReentrant {
    _voteDelay(_tokenId);
    require(IVoteEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
    address[] memory _marketVote = marketVote[_tokenId];
    uint _marketCnt = _marketVote.length;
    uint256[] memory _weights = new uint256[](_marketCnt);

    for (uint i = 0; i < _marketCnt; i++) {
      _weights[i] = votes[_tokenId][_marketVote[i]];
    }

    _vote(_tokenId, _marketVote, _weights);
    lastVoted[_tokenId] = _epochTimestamp() + 1;
  }

  /// @notice Vote for markets
  /// @param  _tokenId    veNFT tokenID used to vote
  /// @param  _marketVote   array of gauges target addresses
  /// @param  _weights    array of weights for each gauge target
  function vote(uint _tokenId, address[] calldata _marketVote, uint256[] calldata _weights) external nonReentrant {
    _voteDelay(_tokenId);
    require(IVoteEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
    require(_marketVote.length == _weights.length);
    _vote(_tokenId, _marketVote, _weights);
    lastVoted[_tokenId] = _epochTimestamp() + 1;
  }

  function _vote(uint _tokenId, address[] memory _marketVote, uint256[] memory _weights) internal {
    _reset(_tokenId);
    uint _marketCnt = _marketVote.length;
    uint256 _weight = IVoteEscrow(_ve).balanceOfNFT(_tokenId);
    uint256 _totalVoteWeight = 0;
    uint256 _totalWeight = 0;
    uint256 _usedWeight = 0;
    uint256 _time = _epochTimestamp();

    for (uint i = 0; i < _marketCnt; i++) {
      _totalVoteWeight += _weights[i];
    }

    for (uint i = 0; i < _marketCnt; i++) {
      address _market = _marketVote[i];
      address _gauge = gauges[_market];

      if (isGauge[_gauge] && isAlive[_gauge]) {
        uint256 _marketWeight = (_weights[i] * _weight) / _totalVoteWeight;
        require(votes[_tokenId][_market] == 0);
        require(_marketWeight != 0);

        marketVote[_tokenId].push(_market);
        weightsPerEpoch[_time][_market] += _marketWeight;

        votes[_tokenId][_market] += _marketWeight;

        _usedWeight += _marketWeight;
        _totalWeight += _marketWeight;
        emit Voted(msg.sender, _tokenId, _marketWeight);
      }
    }
    if (_usedWeight > 0) IVoteEscrow(_ve).voting(_tokenId);
    totWeightsPerEpoch[_time] += _totalWeight;
    usedWeights[_tokenId] = (_usedWeight);
  }

  /// @notice claim LP gauge rewards
  function claimRewards(address[] memory _gauges) external {
    for (uint i = 0; i < _gauges.length; i++) {
      IGauge(_gauges[i]).getReward(msg.sender);
    }
  }

  /// @notice claim bribes rewards given a TokenID
  function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint _tokenId) external {
    require(IVoteEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
    for (uint i = 0; i < _bribes.length; i++) {
      IBribe(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
    }
  }

  /// @notice claim fees rewards given a TokenID
  function claimFees(address[] memory _fees, address[][] memory _tokens, uint _tokenId) external {
    require(IVoteEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
    for (uint i = 0; i < _fees.length; i++) {
      IBribe(_fees[i]).getRewardForOwner(_tokenId, _tokens[i]);
    }
  }

  /// @notice claim bribes rewards given an address
  function claimBribes(address[] memory _bribes, address[][] memory _tokens) external {
    for (uint i = 0; i < _bribes.length; i++) {
      IBribe(_bribes[i]).getRewardForAddress(msg.sender, _tokens[i]);
    }
  }

  /// @notice claim fees rewards given an address
  function claimFees(address[] memory _bribes, address[][] memory _tokens) external {
    for (uint i = 0; i < _bribes.length; i++) {
      IBribe(_bribes[i]).getRewardForAddress(msg.sender, _tokens[i]);
    }
  }

  /// @notice attach a veNFT tokenID to a gauge. This is used for boost farming
  /// @dev boost not available in Ionic. Keep the function in case we need it for future updates.
  function attachTokenToGauge(uint tokenId, address account) external {
    require(isGauge[msg.sender]);
    require(isAlive[msg.sender]); // killed gauges cannot attach tokens to themselves
    if (tokenId > 0) IVoteEscrow(_ve).attach(tokenId);
    emit Attach(account, msg.sender, tokenId);
  }

  /// @notice detach a veNFT tokenID to a gauge. This is used for boost farming
  /// @dev boost not available in Ionic. Keep the function in case we need it for future updates.
  function detachTokenFromGauge(uint tokenId, address account) external {
    require(isGauge[msg.sender]);
    if (tokenId > 0) IVoteEscrow(_ve).detach(tokenId);
    emit Detach(account, msg.sender, tokenId);
  }

  /// @notice check if user can vote
  function _voteDelay(uint _tokenId) internal view {
    require(block.timestamp > lastVoted[_tokenId] + VOTE_DELAY, "ERR: VOTE_DELAY");
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    GAUGE CREATION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */
  /// @notice create multiple gauges
  function createGauges(
    address[] memory _markets,
    uint256[] memory _gaugeTypes
  ) external nonReentrant returns (address[] memory, address[] memory, address[] memory) {
    require(_markets.length == _gaugeTypes.length);
    require(_markets.length <= 10);
    address[] memory _gauge = new address[](_markets.length);
    address[] memory _int = new address[](_markets.length);
    address[] memory _ext = new address[](_markets.length);

    uint i = 0;
    for (i; i < _markets.length; i++) {
      (_gauge[i], _int[i], _ext[i]) = _createGauge(_markets[i], _gaugeTypes[i]);
    }
    return (_gauge, _int, _ext);
  }

  /// @notice create a gauge
  function createGauge(
    address _market,
    uint256 _gaugeType
  ) external nonReentrant returns (address _gauge, address _internal_bribe, address _external_bribe) {
    (_gauge, _internal_bribe, _external_bribe) = _createGauge(_market, _gaugeType);
  }

  /// @notice create a gauge
  /// @param  _target  gauge target address
  /// @param  _gaugeType  the type of the gauge you want to create
  /// @dev    To create stable/Volatile pair gaugeType = 0, Concentrated liqudity = 1, ...
  ///         Make sure to use the corrcet gaugeType or it will fail

  function _createGauge(
    address _target,
    uint256 _gaugeType
  ) internal returns (address _gauge, address _internal_bribe, address _external_bribe) {
    require(_gaugeType < factories.length, "gaugetype");
    require(gauges[_target] == address(0x0), "!exists");
    address _factory = factories[_gaugeType];
    address _gaugeFactory = gaugeFactories[_gaugeType];
    require(_factory != address(0));
    require(_gaugeFactory != address(0));

    //address underlying = IMarket(_target).underlying();

    // gov can create for any target, even non-Ionic pairs
    if (!isGovernor()) {
      // TODO verify that the target is an Ionic market in case the caller is not an admin
      revert("TODO verify that the target is an Ionic market in case the caller is not an admin");
    }

    // create internal and external bribe
    address _owner = owner();
    string memory _type = string.concat("Ionic market Fees: ", IERC20(_target).symbol());
    _internal_bribe = IBribeFactory(bribeFactory).createBribe(_owner, _target, _type);

    _type = string.concat("Ionic Bribes: ", IERC20(_target).symbol());
    _external_bribe = IBribeFactory(bribeFactory).createBribe(_owner, _target, _type);

    // create gauge
    _gauge = IGaugeFactory(_gaugeFactory).createGauge(
      base,
      _ve,
      _target,
      address(this),
      _internal_bribe,
      _external_bribe
    );

    // approve spending for $ion
    IERC20(base).approve(_gauge, type(uint).max);

    // save data
    internal_bribes[_gauge] = _internal_bribe;
    external_bribes[_gauge] = _external_bribe;
    gauges[_target] = _gauge;
    marketForGauge[_gauge] = _target;
    isGauge[_gauge] = true;
    isAlive[_gauge] = true;
    markets.push(_target);

    // update index
    supplyIndex[_gauge] = index; // new users are set to the default global state

    emit GaugeCreated(_gauge, msg.sender, _internal_bribe, _external_bribe, _target);
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VIEW FUNCTIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  /// @notice view the total length of the markets
  function length() external view returns (uint) {
    return markets.length;
  }

  /// @notice view the total length of the voted markets given a tokenId
  function marketVoteLength(uint tokenId) external view returns (uint) {
    return marketVote[tokenId].length;
  }

  function _factories() external view returns (address[] memory) {
    return factories;
  }

  function factoryLength() external view returns (uint) {
    return factories.length;
  }

  function _gaugeFactories() external view returns (address[] memory) {
    return gaugeFactories;
  }

  function gaugeFactoriesLength() external view returns (uint) {
    return gaugeFactories.length;
  }

  function weights(address _market) public view returns (uint) {
    uint _time = _epochTimestamp();
    return weightsPerEpoch[_time][_market];
  }

  function weightsAt(address _market, uint _time) public view returns (uint) {
    return weightsPerEpoch[_time][_market];
  }

  function totalWeight() public view returns (uint) {
    uint _time = _epochTimestamp();
    return totWeightsPerEpoch[_time];
  }

  function totalWeightAt(uint _time) public view returns (uint) {
    return totWeightsPerEpoch[_time];
  }

  function _epochTimestamp() public view returns (uint) {
    return IMinter(minter).active_period();
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  /// @notice notify reward amount for gauge
  /// @dev    the function is called by the minter each epoch. Anyway anyone can top up some extra rewards.
  /// @param  amount  amount to distribute
  function notifyRewardAmount(uint amount) external {
    require(msg.sender == minter);
    _safeTransferFrom(base, msg.sender, address(this), amount); // transfer the distro in
    uint _totalWeight = totalWeightAt(_epochTimestamp() - 604800); // minter call notify after updates active_period, loads votes - 1 week
    uint256 _ratio = 0;

    if (_totalWeight > 0) _ratio = (amount * 1e18) / _totalWeight; // 1e18 adjustment is removed during claim
    if (_ratio > 0) {
      index += _ratio;
    }

    emit NotifyReward(msg.sender, base, amount);
  }

  /// @notice distribute the LP Fees to the internal bribes
  /// @param  _gauges  gauge address where to claim the fees
  /// @dev    the gauge is the owner of the LPs so it has to claim
  function distributeFees(address[] memory _gauges) external {
    for (uint i = 0; i < _gauges.length; i++) {
      if (isGauge[_gauges[i]] && isAlive[_gauges[i]]) {
        IGauge(_gauges[i]).claimFees();
      }
    }
  }

  /// @notice Distribute the emission for ALL gauges
  function distributeAll() external nonReentrant {
    IMinter(minter).update_period();

    uint x = 0;
    uint stop = markets.length;
    for (x; x < stop; x++) {
      _distribute(gauges[markets[x]]);
    }
  }

  /// @notice distribute the emission for N gauges
  /// @param  start   start index point of the markets array
  /// @param  finish  finish index point of the markets array
  /// @dev    this function is used in case we have too many markets and gasLimit is reached
  function distribute(uint start, uint finish) public nonReentrant {
    IMinter(minter).update_period();
    for (uint x = start; x < finish; x++) {
      _distribute(gauges[markets[x]]);
    }
  }

  /// @notice distribute reward onyl for given gauges
  /// @dev    this function is used in case some distribution fails
  function distribute(address[] memory _gauges) external nonReentrant {
    IMinter(minter).update_period();
    for (uint x = 0; x < _gauges.length; x++) {
      _distribute(_gauges[x]);
    }
  }

  /// @notice distribute the emission
  function _distribute(address _gauge) internal {
    uint lastTimestamp = gaugesDistributionTimestamp[_gauge];
    uint currentTimestamp = _epochTimestamp();
    if (lastTimestamp < currentTimestamp) {
      _updateForAfterDistribution(_gauge); // should set claimable to 0 if killed

      uint _claimable = claimable[_gauge];

      // distribute only if claimable is > 0, currentEpoch != lastepoch and gauge is alive
      if (_claimable > 0 && isAlive[_gauge]) {
        claimable[_gauge] = 0;
        gaugesDistributionTimestamp[_gauge] = currentTimestamp;
        IGauge(_gauge).notifyRewardAmount(base, _claimable);
        emit DistributeReward(msg.sender, _gauge, _claimable);
      }
    }
  }

  /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    HELPERS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

  /// @notice update info for gauges
  /// @dev    this function track the gauge index to emit the correct $ion amount after the distribution
  function _updateForAfterDistribution(address _gauge) private {
    address _market = marketForGauge[_gauge];
    uint256 _time = _epochTimestamp() - 604800;
    uint256 _supplied = weightsPerEpoch[_time][_market];

    if (_supplied > 0) {
      uint _supplyIndex = supplyIndex[_gauge];
      uint _index = index; // get global index0 for accumulated distro
      supplyIndex[_gauge] = _index; // update _gauge current position to global position
      uint _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
      if (_delta > 0) {
        uint _share = (uint(_supplied) * _delta) / 1e18; // add accrued difference for each supplied token
        if (isAlive[_gauge]) {
          claimable[_gauge] += _share;
        }
      }
    } else {
      supplyIndex[_gauge] = index; // new users are set to the default global state
    }
  }

  /// @notice safeTransfer function
  /// @dev    implemented safeTransfer function from openzeppelin to remove a bit of bytes from code
  function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
    require(token.code.length > 0);
    (bool success, bytes memory data) = token.call(
      abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
    );
    require(success && (data.length == 0 || abi.decode(data, (bool))));
  }
}
