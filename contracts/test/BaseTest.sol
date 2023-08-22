// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

import "../interfaces/IBribeFactory.sol";
import "../factories/GaugeFactory.sol";
import { Voter } from "../Voter.sol";
import { VoteEscrow } from "../VoteEscrow.sol";
import "../EpochsTimer.sol";

contract IonicToken is ERC20 {
  constructor() ERC20("IONIC", "ION", 18) {}

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}

contract IonicFlywheel is IFlywheel {
  IERC20 public rewardToken;
  address public flywheelRewards;

  constructor(address _rewards) {
    flywheelRewards = _rewards;
  }

  function accrue(IERC20, address) public returns (uint256) {
    return 0;
  }

  function claimRewards(address) public {}
}

contract BaseTest is Test {
  GaugeFactory public gaugeFactory;
  Voter public voter;
  VoteEscrow public ve;
  EpochsTimer timer;
  IonicToken ionicToken;
  address proxyAdmin = address(123);
  address bridge1 = address(321);

  function setUp() public {
    ionicToken = new IonicToken();

    VoterRolesAuthority voterRolesAuthImpl = new VoterRolesAuthority();
    TransparentUpgradeableProxy rolesAuthProxy = new TransparentUpgradeableProxy(
      address(voterRolesAuthImpl),
      proxyAdmin,
      ""
    );
    VoterRolesAuthority voterRolesAuth = VoterRolesAuthority(address(rolesAuthProxy));
    voterRolesAuth.initialize(address(this));

    {
      GaugeFactory impl = new GaugeFactory();
      TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyAdmin, "");
      gaugeFactory = GaugeFactory(address(proxy));
      gaugeFactory.initialize(voterRolesAuth);
    }

    {
      VoteEscrow veImpl = new VoteEscrow();
      TransparentUpgradeableProxy veProxy = new TransparentUpgradeableProxy(address(veImpl), proxyAdmin, "");
      ve = VoteEscrow(address(veProxy));

      // TODO use BAL8020 on a fork?
      address lockedToken = address(ionicToken);
      ve.initialize("veIonic", "veION", lockedToken);
    }

    vm.chainId(ve.ARBITRUM_ONE());
    // advance it time
    vm.warp(200 weeks);

    {
      EpochsTimer timerImpl = new EpochsTimer();
      TransparentUpgradeableProxy timerProxy = new TransparentUpgradeableProxy(address(timerImpl), proxyAdmin, "");
      timer = EpochsTimer(address(timerProxy));
      timer.initialize();
      timer.update_period();
    }

    // TODO
    IBribeFactory bribeFactory = IBribeFactory(address(0));

    Voter voterImpl = new Voter();
    TransparentUpgradeableProxy voterProxy = new TransparentUpgradeableProxy(address(voterImpl), proxyAdmin, "");
    voter = Voter(address(voterProxy));
    voter.initialize(address(ve), address(gaugeFactory), address(bribeFactory), address(timer), voterRolesAuth);

    ve.setVoter(address(voter));

    vm.prank(ve.owner());
    ve.addBridge(bridge1);
  }

  // VoteEscrow
  // [METADATA STORAGE]
  function testVersion() public {
    string memory version = ve.version();

    assertEq(version, "1.0.0", "testVersion/incorrect-version");
  }

  function testSetTeam() public {
    address newTeam = address(999);

    ve.setTeam(newTeam);

    assertEq(newTeam, address(999), "testSetTeam/incorrect-team");
  }

  function testTokenURI() public {
    vm.expectRevert("Query for nonexistent token");

    string memory uri = ve.tokenURI(555);

    // TODO returns empty URI for existing tokens
  }

  // [ERC721 BALANCE/OWNER STORAGE]
  function testOwnerOf() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    address owner = ve.ownerOf(tokenId);

    assertEq(owner, address(this), "testOwnerOf/incorrect-owner");
  }

  function testBalanceOf() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    uint256 balance = ve.balanceOf(address(this));

    assertEq(balance, 1, "testOwnerOf/incorrect-balance");
  }

  // [ERC721 APPROVAL STORAGE]
  function testApprovals() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    address approveAddress = address(999);

    ve.approve(approveAddress, tokenId);

    address approvedAddress = ve.getApproved(tokenId);

    assertEq(approveAddress, approvedAddress, "testApprovals/incorrect-approval");

    ve.setApprovalForAll(approveAddress, true);

    bool approvalStatus = ve.isApprovedForAll(address(this), approveAddress);

    assertEq(approvalStatus, true, "testApprovals/incorrect-approval-status");

    bool isApprovedOrOwner = ve.isApprovedOrOwner(approveAddress, tokenId);

    assertEq(isApprovedOrOwner, true, "testApprovals/incorrect-isApprovedOrOwner-status");

    isApprovedOrOwner = ve.isApprovedOrOwner(address(888), tokenId); // random address

    assertEq(isApprovedOrOwner, false, "testApprovals/incorrect-isApprovedOrOwner-random-address");
  }

  // [ERC721 LOGIC]
  function testTransferFrom() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    address receiverOfTransfer = address(999);

    uint256 ownershipsChangeBefore = ve.ownership_change(tokenId);
    assertEq(ownershipsChangeBefore, 0, "testTransferFrom/incorrect-ownership-change-before");

    ve.transferFrom(address(this), receiverOfTransfer, tokenId);

    uint256 ownershipsChangeAfter = ve.ownership_change(tokenId);
    assertEq(ownershipsChangeAfter, 1, "testTransferFrom/incorrect-ownership-change-after");

    assertEq(ve.balanceOf(address(this)), 0, "testTransferFrom/incorrect-sender-balance");
    assertEq(ve.balanceOf(receiverOfTransfer), 1, "testTransferFrom/incorrect-receiver-balance");

    vm.prank(receiverOfTransfer);

    ve.safeTransferFrom(receiverOfTransfer, address(444), tokenId);
    assertEq(ve.balanceOf(address(444)), 1, "testTransferFrom/incorrect-safeTransfer-balance");
  }

  // [ERC165 LOGIC]
  function testSupportsInterface() public {
    vm.chainId(ve.ARBITRUM_ONE());

    bool value = ve.supportsInterface(0x01ffc9a7);

    assertEq(value, true, "testSupportsInterface/invalid-interface");
  }

  // [INTERNAL MINT/BURN LOGIC]
  function testTokenOfOwnerByIndex() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    uint256 tokenIdStored = ve.tokenOfOwnerByIndex(address(this), 0);

    assertEq(tokenId, tokenIdStored, "testTokenOfOwnerByIndex/invalid-index-or-token");
  }

  // [GAUGE VOTING STORAGE]
  function testLockDurationEffect() public {
    vm.chainId(ve.ARBITRUM_ONE());

    address signer1 = address(444);

    // both addresses create locks with different lock time
    ionicToken.mint(address(this), 100e18);
    ionicToken.mint(signer1, 100e18);

    ionicToken.approve(address(ve), 100e18);
    vm.prank(signer1);
    ionicToken.approve(address(ve), 100e18);

    uint256 tokenId1 = ve.create_lock(100e18, 52 weeks);
    vm.prank(signer1);
    uint256 tokenId2 = ve.create_lock(100e18, 26 weeks);

    // signer1 should have less weight because of less lock time
    assertApproxEqAbs(ve.balanceOfNFT(tokenId1), 100e18, 1e18, "testLockDurationEffect/wrong-nft-weight");
    assertApproxEqAbs(ve.balanceOfNFTAt(tokenId2, block.timestamp), 50e18, 1e18, "testLockDurationEffect/wrong-nft-at-weight");
    assertApproxEqAbs(ve.balanceOfAtNFT(tokenId1, block.number), 100e18, 1e18, "testLockDurationEffect/wrong-at-nft-weight");
    assertApproxEqAbs(ve.totalSupplyAt(block.number), 150e18, 2e18, "testLockDurationEffect/wrong-supply-at-weight");
    assertApproxEqAbs(ve.totalSupplyAtT(block.timestamp), 150e18, 2e18, "testLockDurationEffect/wrong-supply-at-t-weight");
  }

  function testMergeSplit() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 100e18);

    uint256 tokenId0 = ve.create_lock(70e18, 26 weeks);
    uint256 tokenId1 = ve.create_lock(30e18, 52 weeks);

    ve.merge(tokenId0, tokenId1);

    vm.expectRevert("ERC721: invalid token ID");
    ve.ownerOf(tokenId0);
    
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 40e18;
    amounts[1] = 60e18;
    ve.split(amounts, tokenId1);

    assertEq(ve.ownerOf(3), address(this), "testMergeSplit/invalid-split");
    assertEq(ve.ownerOf(4), address(this), "testMergeSplit/invalid-split");
  }

  // [ESCROW LOGIC]
  function testIonicLockAndVotingPower() public {
    uint256 tokenId;

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    // change to some other chain ID
    vm.chainId(1);

    vm.expectRevert("wrong chain id");
    tokenId = ve.create_lock(20e18, 52 weeks);

    // revert back to the master chain ID
    vm.chainId(ve.ARBITRUM_ONE());
    tokenId = ve.create_lock(20e18, 52 weeks);

    assertApproxEqAbs(ve.balanceOfNFT(tokenId), 20e18, 1e17, "wrong voting power");
  }

  function _helperCreateLock() internal returns (uint256 tokenId) {
    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    vm.chainId(ve.ARBITRUM_ONE());

    tokenId = ve.create_lock(20e18, 2 weeks);
  }

  function testIonicLockTimeIncrease() public {
    uint256 tokenId = _helperCreateLock();

    (int128 previousAmount, uint256 previousEnd) = ve.locked(tokenId);

    ve.increase_unlock_time(tokenId, 4 weeks);

    (int128 newAmount, uint256 newEnd) = ve.locked(tokenId);

    assertGt(newEnd, previousEnd, "newEnd less or equal");
    assertEq(int(newAmount), int(previousAmount), "amounts not equal");
  }

  function testIonicLockAmountIncrease() public {
    uint256 tokenId = _helperCreateLock();

    (int128 previousAmount, uint256 previousEnd) = ve.locked(tokenId);

    ve.increase_amount(tokenId, 20e18);

    (int128 newAmount, uint256 newEnd) = ve.locked(tokenId);

    assertEq(newEnd, previousEnd, "ends not equal");
    assertGt(int(newAmount), int(previousAmount), "newAmount less or equal");
  }

  function testIonicWithdraw() public {
    uint256 tokenId = _helperCreateLock();

    address owner = ve.ownerOf(tokenId);

    assertEq(owner, address(this), "testIonicWithdraw/wrong-owner");
    
    vm.warp(block.timestamp + 53 weeks);

    ve.withdraw(tokenId);

    vm.expectRevert("ERC721: invalid token ID");
    ve.ownerOf(tokenId);
  }

  function testCreateMarketGauges() public {
    address rewardsContract = address(922);
    address market = address(444);
    uint256 rewardsAmount = 233e18;
    IonicFlywheel flywheel = new IonicFlywheel(rewardsContract);

    // fund the user with some ION
    ionicToken.mint(address(this), 1000e18);

    // create the market gauge
    (address gaugeAddress, , ) = voter.createMarketGauge(market, address(flywheel));
    MarketGauge marketGauge = MarketGauge(gaugeAddress);

    // create the lock
    ionicToken.approve(address(ve), 1e36);
    uint256 tokenId = ve.create_lock(20e18, 52 weeks);
    voter.vote(tokenId, asArray(market), asArray(1e18));

    // let the new epoch start
    vm.warp(block.timestamp + 2 weeks + 1);

    // send some rewards for the past epoch
    ionicToken.approve(address(voter), 1e36);
    voter.notifyRewardAmount(rewardsAmount);

    // distribute the rewards for the past epoch
    voter.distributeAll();

    // check if the flywheel rewards contract is funded
    uint256 rewardsContractBalance = ionicToken.balanceOf(rewardsContract);
    assertApproxEqAbs(rewardsContractBalance, rewardsAmount, 1e10, "!rewards contract balance");
  }

  function asArray(address value) public pure returns (address[] memory) {
    address[] memory array = new address[](1);
    array[0] = value;
    return array;
  }

  function asArray(uint256 value0, uint256 value1) public pure returns (uint256[] memory) {
    uint256[] memory array = new uint256[](2);
    array[0] = value0;
    array[1] = value1;
    return array;
  }

  function asArray(uint256 value) public pure returns (uint256[] memory) {
    uint256[] memory array = new uint256[](1);
    array[0] = value;
    return array;
  }
}
