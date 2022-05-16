// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ERC20.sol";
import "./utils/SafeERC20.sol";
import "./interfaces/IERC4626.sol";

contract DummyVault is ERC20, IERC4626 {
    IERC20Metadata private immutable _underlying;

    constructor (IERC20Metadata __underlying)ERC20("yvaultUSDC", "USDC vault") {
        _underlying = __underlying;
    }

    function token() public view virtual override returns (address) {
        return address(_underlying);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return _underlying.balanceOf(address(this));
    }

    function pricePerShare() public view virtual override returns (uint256) {
        return _sharesToAssets(10 ** decimals());
    }

    function assetsOf(address depositor) public view virtual override returns (uint256) {
        return totalAssets() * balanceOf(depositor) / totalSupply();
    }

    function maxDeposit(address /*caller*/) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return _assetsToShares(assets);
    }

    function deposit(uint256 amount) public virtual override returns (uint256) {
        uint256 shares = previewDeposit(amount);
        SafeERC20.safeTransferFrom(_underlying, _msgSender(), address(this), amount);
        _mint(_msgSender(), shares);
        return shares;
    }

    function maxMint(address /*caller*/) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _sharesToAssets(shares);
    }

    // function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
    //     uint256 assets = _sharesToAssets(shares);
    //     SafeERC20.safeTransferFrom(_underlying, _msgSender(), address(this), assets);
    //     _mint(receiver, shares);
    //     return assets;
    // }

    function maxWithdraw(address caller) public view virtual override returns (uint256) {
        return assetsOf(caller);
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return _assetsToShares(assets);
    }

    // function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
    //     address sender = _msgSender();
    //     uint256 shares = previewWithdraw(assets);

    //     if (sender != owner) {
    //         uint256 currentAllowance = allowance(owner, sender);
    //         if (currentAllowance != type(uint256).max) {
    //             require(currentAllowance >= shares, "ERC20: transfer amount exceeds allowance");
    //             _approve(owner, sender, currentAllowance - shares);
    //         }
    //     }

    //     _burn(owner, shares);
    //     SafeERC20.safeTransfer(_underlying, receiver, assets);
    //     return shares;
    // }

    function maxRedeem(address caller) public view virtual override returns (uint256) {
        return balanceOf(caller);
    }

    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _sharesToAssets(shares);
    }

    function withdraw(uint256 amount) public virtual override returns (uint256) {
        address sender = _msgSender();
        uint256 assets = previewRedeem(amount);

        _burn(sender, amount);
        SafeERC20.safeTransfer(_underlying, sender, assets);
        return assets;
    }

    function _sharesToAssets(uint256 shares) internal view virtual returns (uint256) {
        return totalAssets() == 0 && totalSupply() == 0
            ? shares * (10 ** _underlying.decimals()) / (10 ** decimals())
            : shares * totalAssets() / totalSupply();
    }

    function _assetsToShares(uint256 assets) internal view virtual returns (uint256) {
        return totalAssets() == 0 && totalSupply() == 0
            ? assets * (10 ** decimals()) / (10 ** _underlying.decimals())
            : assets * totalSupply() / totalAssets();
    }
}