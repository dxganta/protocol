// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.4;

import "../Ownable.sol"; // temporary
// import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./assets/AAVEAssetP0.sol";
import "./assets/ATokenAssetP0.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IMain.sol";
import "./interfaces/IVault.sol";

/*
 * @title VaultP0
 * @notice An issuer of an internal bookkeeping unit called a BU or basket unit.
 */
contract VaultP0 is IVault, Ownable {
    using SafeERC20 for IERC20;

    uint8 public constant BUDecimals = 18;

    Basket internal _basket;

    mapping(address => mapping(address => uint256)) internal _allowances;
    mapping(address => uint256) public override basketUnits;
    uint256 public totalUnits;

    IVault[] public backups;

    IMain public main;

    constructor(
        IAsset[] memory assets,
        uint256[] memory quantities,
        IVault[] memory backupVaults
    ) {
        require(assets.length == quantities.length, "arrays must match in length");

        // Set default immutable basket
        _basket.size = assets.length;
        for (uint256 i = 0; i < _basket.size; i++) {
            _basket.assets[i] = assets[i];
            _basket.quantities[assets[i]] = quantities[i];
        }

        backups = backupVaults;
    }

    /// @notice Transfers collateral in and issues a quantity of BUs to the caller
    /// @param to The account to transfer collateral to
    /// @param amount The quantity of BUs to issue
    function issue(address to, uint256 amount) external override {
        require(amount > 0, "Cannot issue zero");
        require(_basket.size > 0, "Empty basket");

        uint256[] memory amounts = tokenAmounts(amount);

        for (uint256 i = 0; i < _basket.size; i++) {
            _basket.assets[i].erc20().safeTransferFrom(_msgSender(), address(this), amounts[i]);
        }

        basketUnits[to] += amount;
        totalUnits += amount;
        emit BUIssuance(to, _msgSender(), amount);
    }

    /// @notice Redeems a quantity of BUs and transfers collateral out
    /// @param to The account to transfer collateral to
    /// @param amount The quantity of BUs to redeem
    function redeem(address to, uint256 amount) external override {
        require(amount > 0, "Cannot redeem zero");
        require(amount <= basketUnits[_msgSender()], "Not enough units");
        require(_basket.size > 0, "Empty basket");

        uint256[] memory amounts = tokenAmounts(amount);

        basketUnits[_msgSender()] -= amount;
        totalUnits -= amount;

        for (uint256 i = 0; i < _basket.size; i++) {
            _basket.assets[i].erc20().safeTransfer(to, amounts[i]);
        }
        emit BURedemption(to, _msgSender(), amount);
    }

    /// @notice Allows `spender` to spend `amount` from the callers account
    /// @param spender The account that is able to spend the `amount`
    /// @param amount The quantity of BUs that should be spendable
    function setAllowance(address spender, uint256 amount) external override {
        _allowances[_msgSender()][spender] = amount;
    }

    /// @notice Pulls BUs over from one account to another (like `ERC20.transferFrom`), requiring allowance
    /// @param from The account to pull BUs from (must have set allowance)
    /// @param amount The quantity of BUs to pull
    function pullBUs(address from, uint256 amount) external override {
        require(basketUnits[from] >= amount, "not enough to transfer");
        require(_allowances[from][_msgSender()] >= amount, "not enough allowance");
        _allowances[from][_msgSender()] -= amount;
        basketUnits[from] -= amount;
        basketUnits[_msgSender()] += amount;
        emit BUTransfer(from, _msgSender(), amount);
    }

    /// @notice Claims all earned COMP/AAVE and sends it to the asset manager
    function claimAndSweepRewardsToManager() external override {
        require(address(main) != address(0), "main not set");

        // Claim
        main.comptroller().claimComp(address(this));
        IStaticAToken(address(main.aaveAsset().erc20())).claimRewardsToSelf(true);

        // Sweep
        IERC20 comp = main.compAsset().erc20();
        uint256 compBal = comp.balanceOf(address(this));
        if (compBal > 0) {
            comp.safeTransfer(address(main.manager()), compBal);
        }
        IERC20 aave = main.aaveAsset().erc20();
        uint256 aaveBal = aave.balanceOf(address(this));
        if (aaveBal > 0) {
            aave.safeTransfer(address(main.manager()), aaveBal);
        }
        emit ClaimRewards(compBal, aaveBal);
    }

    /// @notice Forces an update of rates in the Compound/Aave protocols, call before `basketRate()` for recent rates
    function updateCompoundAaveRates() external override {
        for (uint256 i = 0; i < _basket.size; i++) {
            _basket.assets[i].updateRedemptionRate();
        }
    }

    /// @return parts A list of token quantities required in order to issue `amount` BUs
    function tokenAmounts(uint256 amount) public view override returns (uint256[] memory parts) {
        parts = new uint256[](_basket.size);
        for (uint256 i = 0; i < _basket.size; i++) {
            parts[i] = (amount * _basket.quantities[_basket.assets[i]]) / 10**BUDecimals;
        }
    }

    /// @return sum The combined fiatcoin worth of one BU
    function basketRate() external view override returns (uint256 sum) {
        for (uint256 i = 0; i < _basket.size; i++) {
            IAsset c = _basket.assets[i];
            sum += (_basket.quantities[c] * c.redemptionRate()) / 10**c.decimals();
        }
    }

    /// @return Whether the vault is made up only of collateral in `assets`
    function containsOnly(address[] memory assets) external view override returns (bool) {
        for (uint256 i = 0; i < _basket.size; i++) {
            bool found = false;
            for (uint256 j = 0; j < assets.length; j++) {
                if (address(_basket.assets[i]) == assets[j]) {
                    found = true;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    /// @return The maximum number of BUs the caller can issue
    function maxIssuable(address issuer) external view override returns (uint256) {
        uint256 min = type(uint256).max;
        for (uint256 i = 0; i < _basket.size; i++) {
            uint256 BUs = _basket.assets[i].erc20().balanceOf(issuer) / _basket.quantities[_basket.assets[i]];
            if (BUs < min) {
                min = BUs;
            }
        }
        return min;
    }

    /// @return The asset at `index`
    function assetAt(uint256 index) external view override returns (IAsset) {
        return _basket.assets[index];
    }

    /// @return The size of the basket
    function size() external view override returns (uint256) {
        return _basket.size;
    }

    /// @return The quantity of tokens of `asset` required to create 1e18 BUs
    function quantity(IAsset asset) external view override returns (uint256) {
        return _basket.quantities[asset];
    }

    /// @return A list of eligible backup vaults
    function getBackups() external view override returns (IVault[] memory) {
        return backups;
    }

    function setBackups(IVault[] memory backupVaults) external onlyOwner {
        backups = backupVaults;
    }

    function setMain(IMain main_) external onlyOwner {
        main = main_;
    }
}