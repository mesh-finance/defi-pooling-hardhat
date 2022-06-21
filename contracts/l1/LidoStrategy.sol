// SPDX-License-Identifier: MIT
pragma solidity 0.7.4;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IStETH.sol";
import "./interfaces/IWstETH.sol";
import "./interfaces/IStarknetCore.sol";
import "./interfaces/IStarknetETHBridge.sol";


/**
 * This strategy bridge an asset ETH, deposits into lido finance. 
 */
contract LidoStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 constant MESSAGE_WITHDRAWAL_REQUEST = 1;
    uint256 constant MESSAGE_DEPOSIT_REQUEST = 2;
    uint256 constant DISTRIBUTION_CONFIRMATION = 3;

    //  from starkware.starknet.compiler.compile import get_selector_from_name
    //  print(get_selector_from_name('handle_distribute_underlying'))
    uint256 constant DISTRIBUTE_UNDERLYING_SELECTOR =
        823752107113310000093673478517431453452746400890662466658548911690286052542;

    //  from starkware.starknet.compiler.compile import get_selector_from_name
    //  print(get_selector_from_name('handle_distribute_share'))
    uint256 constant DISTRIBUTE_SHARES_SELECTOR =
        43158444020691042243121819418379972480051290998360791401029726400163460126;

    // address public immutable  underlying;
    address public governor;
    IStarknetCore public immutable  starknetCore;
    IStarknetETHBridge public immutable starknetETHBridge;
    uint256 public immutable  l2Contract;

    address public pendingGovernor;
    // the stETH contract for depositing ETH for stETH
    IStETH public stETH;
    // wstETH for wrapping stETH to wstETH
    IWstETH public wstETH;
    // referral address for lido referral program
    address public referralAddress;

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;
    // mapping to store bridgeAmount for each id
    mapping(uint256 => uint256) public bridgingAmount;

    event GovernancePushed(address indexed oldGovernor, address indexed pendingGovernor);
    event GovernanceChanged(address indexed oldGovernor, address indexed newGovernor);
    event Deposited(uint256 indexed depositId, uint256 depositAmount, uint256 stETHReceived, uint256 wstETHReceived);
    event Withdrawed(uint256 indexed withdrawId, uint256 sharesWithdrawn, uint256 amountReceived);
    event DistributedOnL2(uint256 indexed withdrawId, uint256 bridgedAmount);


    constructor(address _stETH, address _wstETH, address _starknetCore, uint256 _l2Contract, address _starknetETHBridge) {
        require(_stETH != address(0), "stETH cannot be zero");
        require(_wstETH != address(0), "wstETH cannot be zero");
        
        stETH = IStETH(_stETH);
        wstETH = IWstETH(_wstETH);
        governor = msg.sender;
        starknetCore = IStarknetCore(_starknetCore);
        starknetETHBridge = IStarknetETHBridge(_starknetETHBridge);
        l2Contract = _l2Contract;

        // restricted tokens, can not be swept
        canNotSweep[_stETH] = true;
        canNotSweep[_wstETH] = true;

    }


    modifier onlyGovernance() {
        require(msg.sender == governor, "The caller has to be the governor");
        _;
    }

    // ******Gonernanace Config*****
    function pushGovernance(address _newGovernor) external onlyGovernance {
        pendingGovernor = _newGovernor;
        emit GovernancePushed(governor, _newGovernor);
    }


    function pullGovernance() external  {
        require(msg.sender == pendingGovernor, "the caller is not authorized");
        emit GovernanceChanged(governor, pendingGovernor);
        governor = pendingGovernor;
        pendingGovernor = address(0);
        
    }



    /**
     * Withdraws ETH from the strategy and bridge back to L2.
     */
    // @Notice lido vault doesn't have a withdraw function untill ETH 2.0 becon 
    // chain is launched, So instead the strategy will sell the stETH for ETH in Crv
    function withdrawAndBridgeBack(uint256 id, uint256 shares)
        external
        onlyGovernance
    {

        // Construct the withdrawal message's payload.
        uint256[] memory payload = new uint256[](4);
        payload[0] = MESSAGE_WITHDRAWAL_REQUEST;
        payload[1] = id;
        (payload[2], payload[3]) = toSplitUint(shares);

        // Consume the message from the StarkNet core contract.
        // This will revert the (Ethereum) transaction if the message does not exist or already consumed.
        starknetCore.consumeMessageFromL2(l2Contract, payload);

        // keeping record of balance before withdrawing
        uint256 ethBalanceBefore = address(this).balance;

        // approving wstETH to unwrap
        wstETH.approve(address(wstETH),0);
        wstETH.approve(address(wstETH),shares);

        // unwrapping
        uint256 stETHReceived = wstETH.unwrap(shares);

        // NO WITHDRAW FUNCTION
        // stETH.withdraw(stETHReceived);

        uint256 ethBalanceAfter = address(this).balance;

        uint256 amountToBridge = ethBalanceAfter.sub(ethBalanceBefore);

        //bridge ETH
        starknetETHBridge.deposit{value: amountToBridge}(l2Contract);

        // distributing underlying on L2

        // ********APPROACH-1************************
        // ************cant do this as the actual bridging of asset might take time ************
        // might need to create another onlyGovernance function to trigger distribute on L2
        // uint256[] memory payload = new uint256[](2);
        // payload[0] = id;
        // payload[1] = amountToBridge;

        // Send the message to the StarkNet core contract.
        // starknetCore.sendMessageToL2(l2Contract, DISTRIBUTE_UNDERLYING_SELECTOR, payload);
        // *******************************************
        // Note: approach-1 works only if bridging is instantaneous which I think is

        // *********************APPROACH-2********************* 
        // saving the bridging amount for that id in a mapping to call later
        bridgingAmount[id] = amountToBridge;
        // and when the asset is bridge to L2 call distributeUnderlying function with id as params
        // ************************************************************

        emit Withdrawed(id, shares, amountToBridge);
    }

    // @Note: call this function after asset are bridged to L2 for that id.
    function distributeUnderlyingOnL2(uint256 id)
        external
        onlyGovernance
    {
        uint256 bridgeAmount = bridgingAmount[id];
        // will revert if have not call withdrawAndBridgeBack earlier with same id
        require(bridgeAmount > 0, "No amount to bridge"); 
        // checking if already distributed on L2 for the given id
        require(!_verifyDistributionOnL2(id), "Already distributed on L2");

        // confirming the distribution of asset on L2 for previous IDs 
        if(id > 0) {
            require(_verifyDistributionOnL2(id.sub(1)), "Previous request not Processed!");

        }
        // distributing ETH on L2
        uint256[] memory payload2 = new uint256[](3);
        payload2[0] = id;
        (payload2[1], payload2[2]) = toSplitUint(bridgeAmount);

        // Send the message to the StarkNet core contract.
        starknetCore.sendMessageToL2(l2Contract, DISTRIBUTE_UNDERLYING_SELECTOR, payload2);

        // to prevent multiple distribution for same id.
        // @Review : here the problen is that if txn failed on L2, even then bridgingAmount will be updated to zero
        // and thus asset will be locked.
        // @Review : the check is shifted to L2 instead of L1
        // bridgingAmount[id] = 0;

        emit DistributedOnL2(id, bridgeAmount);
    }


    function depositAndDisbtributeSharesOnL2(uint256 id, uint256 amount )
        external
        onlyGovernance
    {
        require(amount > 0, "Cannot deposit zero");
        // uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        // require(underlyingBalance >= amount, "Insufficient asset to deposit"); // it will revert will bridging of asset to L1 is not completed yet

        // Construct the deposit message's payload.
        uint256[] memory payload = new uint256[](4);
        payload[0] = MESSAGE_DEPOSIT_REQUEST;
        payload[1] = id;
        (payload[2], payload[3]) = toSplitUint(amount);

        // Consume the message from the StarkNet core contract.
        // This will revert the (Ethereum) transaction if the message does not exist.
        starknetCore.consumeMessageFromL2(l2Contract, payload);

        // claiming bridged asset on L1
        starknetETHBridge.withdraw(amount, address(this));

        // deposit the ETH to lido vault
        uint256 stETHReceived = stETH.submit{value: amount}(referralAddress);

        // approving stETH to wrap
        stETH.approve(address(wstETH),0);
        stETH.approve(address(wstETH),stETHReceived);

        // wrapping
        uint256 wstETHReceived = wstETH.wrap(stETHReceived);

        // distributing shares on L2 
        // @Note: the actual shares are not bridging to L2, instead we mint mShares of equal amount on L2
        uint256[] memory payload2 = new uint256[](3);
        payload2[0] = id;
        (payload2[1], payload2[2]) = toSplitUint(wstETHReceived);
        // payload2[1] = sharesReceieved;

        // Send the message to the StarkNet core contract.
        starknetCore.sendMessageToL2(l2Contract, DISTRIBUTE_SHARES_SELECTOR, payload2);

        emit Deposited(id, amount, stETHReceived, wstETHReceived);
    }
    
    // no tokens apart from underlying should be sent to this contract. Any tokens that are sent here by mistake are recoverable by governance
    function sweep(address _token, address _sweepTo) external onlyGovernance{
        require(!canNotSweep[_token], "Token is restricted");
        require(_sweepTo != address(0), "can not sweep to zero");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function updateReferralAddress(address _referralAddress) external onlyGovernance {
        referralAddress = _referralAddress;
    }

    /**
     * Returns the underlying invested balance. This is the underlying amount based on stETH balance
     */
    function investedUnderlyingBalance()
        external
        view
        returns (uint256)
    {
        uint256 wstETHBalance = wstETH.balanceOf(address(this));
        uint256 stETHEquivalent = stETH.getPooledEthByShares(wstETHBalance);
        uint256 ETHEquivalent = stETH.getPooledEthByShares(stETHEquivalent);
        return ETHEquivalent;
    }

    /**
     * Returns the value of the underlying token in yToken
     */
    function _shareValueFromUnderlying(uint256 ethAmount)
        internal
        view
        returns (uint256 wstETHEquivalent)
    {
        uint256 stETHEquivalent = stETH.getSharesByPooledEth(ethAmount);
        
        wstETHEquivalent = stETH.getSharesByPooledEth(stETHEquivalent);
    }

    function toSplitUint(uint256 value) internal pure returns (uint256, uint256) {
      uint256 low = value & ((1 << 128) - 1);
      uint256 high = value >> 128;
      return (low, high);
    }

    function _verifyDistributionOnL2(uint256 id) internal view returns (bool) {
        // Construct the distribution confirmation message's payload.
        uint256[] memory payload = new uint256[](2);
        payload[0] = DISTRIBUTION_CONFIRMATION;
        payload[1] = id;

        // This will revert the transaction if the message does not exist or already consumed.
        // @Reviewer: message can be consumed only once so if later in func sendMessageToL2
        // fails, it cant be retrigger again.
        // ***********
        // starknetCore.consumeMessageFromL2(l2Contract, payload);
        // ************

        // Instead of consuming, only checking if the message exists
        bytes32 msgHash = keccak256(
        abi.encodePacked(l2Contract, address(this), payload.length, payload)
        );
        return starknetCore.l2ToL1Messages(msgHash) > 0;

    }

    function verifyDistributionOnL2(uint256 id) external view returns (bool) {
        return _verifyDistributionOnL2(id);
    }

}
