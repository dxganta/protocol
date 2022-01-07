// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "contracts/p0/assets/Asset.sol";
import "contracts/p0/interfaces/IAsset.sol";
import "contracts/p0/interfaces/IMain.sol";
import "contracts/p0/libraries/Oracle.sol";
import "contracts/libraries/Fixed.sol";

/**
 * @title CollateralP0
 * @notice A vanilla asset such as a fiatcoin, to be extended by derivative assets.
 */
contract CollateralP0 is ICollateral, AssetP0 {
    using FixLib for Fix;
    using Oracle for Oracle.Info;

    // underlying == address(0): The collateral is leaf collateral; it has no underlying
    // underlying != address(0): The collateral is derivative collateral; it has underlying collateral
    ICollateral public immutable underlying;

    // Default Status:
    // whenDefault == NEVER: no risk of default (initial value)
    // whenDefault > block.timestamp: delayed default may occur as soon as block.timestamp.
    //                In this case, the asset may recover, reachiving whenDefault == NEVER.
    // whenDefault <= block.timestamp: default has already happened (permanently)
    uint256 internal constant NEVER = type(uint256).max;
    uint256 internal whenDefault = NEVER;
    uint256 internal prevBlock; // Last block when _updateDefaultStatus() was called
    Fix internal prevRate; // Last rate when _updateDefaultStatus() was called

    // solhint-disable-next-list no-empty-blocks
    constructor(
        UoA uoa_,
        IERC20Metadata erc20_,
        IMain main_,
        Oracle.Source oracleSource_
    ) AssetP0(uoa_, erc20_, main_, oracleSource_) {}

    /// Sets `whenDefault`, `prevBlock`, and `prevRate` idempotently
    function forceUpdates() public virtual override {
        _updateDefaultStatus();
    }

    function _updateDefaultStatus() internal {
        if (whenDefault <= block.timestamp || block.number <= prevBlock) {
            // Nothing will change if either we're already fully defaulted
            // or if we've already updated default status this block.
            return;
        }

        // If the redemption rate has fallen, default immediately
        Fix newRate = _rateToUnderlying();
        if (newRate.lt(prevRate)) {
            whenDefault = block.timestamp;
        }

        // If the underlying fiatcoin price is below the default-threshold price, default eventually
        if (whenDefault > block.timestamp) {
            Price memory p = fiatcoinPrice(); // {Price/fiatTok}
            bool fiatcoinIsDefaulting = p.attoUSD.lte(main.defaultingFiatcoinPrice());
            whenDefault = fiatcoinIsDefaulting
                ? Math.min(whenDefault, block.timestamp + main.defaultDelay())
                : NEVER;
        }

        // Cache any lesser updates
        prevRate = newRate;
        prevBlock = block.number;
    }

    /// @return The asset's default status
    function status() public view returns (CollateralStatus) {
        if (whenDefault == 0) {
            return CollateralStatus.SOUND;
        } else if (block.timestamp < whenDefault) {
            return CollateralStatus.IFFY;
        } else {
            return CollateralStatus.DEFAULTED;
        }
    }

    /// @return p {Price/tok} The Price per whole token
    function price() public view virtual override(AssetP0, IAsset) returns (Price memory p) {
        if (address(underlying) == address(0)) {
            return main.oracle(uoa).consult(oracleSource, erc20);
        }

        p = underlying.price();
        // {attoUSD/tok} = {attoUSD/underlyingTok} * {underlyingTok/tok}
        p.attoUSD = p.attoUSD.mul(_rateToUnderlying());
        // {attoEUR/tok} = {attoEUR/underlyingTok} * {underlyingTok/tok}
        p.attoEUR = p.attoEUR.mul(_rateToUnderlying());
    }

    /// @return {Price/tok} The price of 1 whole token of the fiatcoin
    function fiatcoinPrice() public view virtual returns (Price memory) {
        if (address(underlying) == address(0)) {
            return main.oracle(uoa).consult(oracleSource, erc20);
        }

        return underlying.fiatcoinPrice();
    }

    /// @return The ERC20 contract of the (maybe underlying) fiatcoin
    function fiatcoinERC20() public view override returns (IERC20Metadata) {
        if (address(underlying) == address(0)) {
            return erc20;
        }

        return underlying.fiatcoinERC20();
    }

    /// @return {underlyingTok/tok} Conversion rate between token and its underlying.
    function _rateToUnderlying() internal view virtual returns (Fix) {
        return FIX_ONE;
    }
}
