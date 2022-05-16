// SPDX-License-Identifier: MIT
pragma solidity 0.7.4;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IYVaultV2.sol";
import "./interfaces/IStarknetCore.sol";
import "./interfaces/IStarknetERC20Bridge.sol";


/**
 * This strategy takes an asset USDC, deposits into yv2 vault. 
 */
contract YearnV2Strategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 constant MESSAGE_WITHDRAWAL_REQUEST = 1;
    uint256 constant MESSAGE_DEPOSIT_REQUEST = 2;

    // The selector of the "handle_distribute_underlying" l1_handler.
    //  print(get_selector_from_name('handle_distribute_underlying'))
    uint256 constant DISTRIBUTE_UNDERLYING_SELECTOR =
        3520401815844567356085155807608885419463728554843487745; //(dummy value)

    // The selector of the "handle_distribute_share" l1_handler.
    //  print(get_selector_from_name('handle_distribute_share'))
    uint256 constant DISTRIBUTE_SHARES_SELECTOR =
        3520401815844567356085155807608885419463728554843487745; //(dummy value)

    address public immutable  underlying;
    address public governor;
    IStarknetCore public immutable  starknetCore;
    IStarknetERC20Bridge public immutable starknetERC20Bridge;
    uint256 public immutable  l2Contract;

    address public pendingGovernor;
    // the y-vault corresponding to the underlying asset
    address public immutable yVault;

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;
    // mapping to store bridgeAmount for each id
    mapping(uint256 => uint256) public bridgingAmount;

    event GovernancePushed(address oldGovernor, address pendingGovernor);
    event GovernanceChanged(address oldGovernor, address newGovernor);
    event Deposited(uint256 depositId, uint256 depositAmount, uint256 sharesReceived);
    event Withdrawed(uint256 withdrawId, uint256 sharesWithdrawn, uint256 amountReceived);
    event DistributedOnL2(uint256 withdrawId, uint256 bridgedAmount);


    constructor(address _underlying, address _yVault, address _starknetCore, uint256 _l2Contract, address _starknetERC20Bridge) public {
        require(_underlying != address(0), "underlying cannot be empty");
        require(_yVault != address(0), "Yearn Vault cannot be empty");
        require(
            _underlying == IYVaultV2(_yVault).token(),
            "Underlying do not match"
        );
        underlying = _underlying;
        yVault = _yVault;
        governor = msg.sender;
        starknetCore = IStarknetCore(_starknetCore);
        starknetERC20Bridge = IStarknetERC20Bridge(_starknetERC20Bridge);
        l2Contract = _l2Contract;

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;
        canNotSweep[_yVault] = true;

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
     * Withdraws underlying asset from the strategy and bridge back to L2.
     */
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
        // This will revert the (Ethereum) transaction if the message does not exist.
        // TODO: find if message can be consumed more than once or not
        // will need to add check if that possible to prevent multiple txn for same id.
        starknetCore.consumeMessageFromL2(l2Contract, payload);

        // keeping record of balance before withdrawing
        uint256 underlyingBalanceBefore = IERC20(underlying).balanceOf(address(this));

        IYVaultV2(yVault).withdraw(shares);


        // we can bridge back the asset to the L2
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));

        uint256 amountToBridge = underlyingBalance.sub(underlyingBalanceBefore);

        //bridge the asset
        IERC20(underlying).approve(address(starknetERC20Bridge), 0);
        IERC20(underlying).approve(address(starknetERC20Bridge), amountToBridge);
        starknetERC20Bridge.deposit(amountToBridge,l2Contract);

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
        require(bridgeAmount > 0, "No amount to bridge"); 
        // will revert if have not call withdrawAndBridgeBack earlier with same id or already distributed

        // distributing underlying on L2
        uint256[] memory payload = new uint256[](3);
        payload[0] = id;
        (payload[1], payload[2]) = toSplitUint(bridgeAmount);

        // Send the message to the StarkNet core contract.
        starknetCore.sendMessageToL2(l2Contract, DISTRIBUTE_UNDERLYING_SELECTOR, payload);

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
        // @Review: assuming a msg can be consumed only once, if not check has 
        // to be imposed to avoid multiple txn for same id
        starknetCore.consumeMessageFromL2(l2Contract, payload);

        // claiming bridged asset on L1
        starknetERC20Bridge.withdraw(amount, address(this));


        IERC20(underlying).safeApprove(yVault, 0);
        IERC20(underlying).safeApprove(yVault, amount);
        // deposit the underlying to yv2 vault
        uint256 sharesReceieved = IYVaultV2(yVault).deposit(amount);

        // distributing shares on L2 
        // @Note: the actual shares are not bridging to L2, instead we mint mShares of equal amount on L2
        uint256[] memory payload2 = new uint256[](3);
        payload2[0] = id;
        (payload2[1], payload2[2]) = toSplitUint(sharesReceieved);
        // payload2[1] = sharesReceieved;

        // Send the message to the StarkNet core contract.
        starknetCore.sendMessageToL2(l2Contract, DISTRIBUTE_SHARES_SELECTOR, payload2);

        emit Deposited(id, amount, sharesReceieved);
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

    /**
     * Returns the underlying invested balance. This is the underlying amount based on shares in the yv2 vault
     */
    function investedUnderlyingBalance()
        external
        view
        returns (uint256)
    {
        uint256 shares = IERC20(yVault).balanceOf(address(this));
        uint256 price = IYVaultV2(yVault).pricePerShare();
        uint256 precision = 10**(IYVaultV2(yVault).decimals());
        uint256 underlyingBalanceinYVault = shares.mul(price).div(precision);
        return underlyingBalanceinYVault;
    }

    /**
     * Returns the value of the underlying token in yToken
     */
    function _shareValueFromUnderlying(uint256 underlyingAmount)
        internal
        view
        returns (uint256)
    {
        uint256 precision = 10**(IYVaultV2(yVault).decimals());
        return
            underlyingAmount.mul(precision).div(
                IYVaultV2(yVault).pricePerShare()
            );
    }

    function toSplitUint(uint256 value) internal pure returns (uint256, uint256) {
      uint256 low = value & ((1 << 128) - 1);
      uint256 high = value >> 128;
      return (low, high);
    }
}
