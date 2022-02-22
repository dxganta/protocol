// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "contracts/p0/interfaces/IMain.sol";
import "contracts/p0/interfaces/IMarket.sol";
import "contracts/p0/libraries/Rewards.sol";
import "contracts/libraries/Fixed.sol";

abstract contract TraderP0 is ITraderEvents {
    using FixLib for Fix;
    using SafeERC20 for IERC20Metadata;

    Auction[] public auctions;

    uint256 private countOpenAuctions;

    IMain public main;

    function initTrader(address main_) internal virtual {
        main = IMain(main_);
    }

    /// @return true iff this trader now has open auctions.
    function hasOpenAuctions() public view returns (bool) {
        return countOpenAuctions > 0;
    }

    /// Settle any auctions that are due (past their end time)
    function closeDueAuctions() internal {
        // Closeout open auctions or sleep if they are still ongoing.
        for (uint256 i = 0; i < auctions.length; i++) {
            Auction storage auction = auctions[i];
            if (auction.status == AuctionStatus.OPEN && block.timestamp >= auction.endTime) {
                closeAuction(i);
            }
        }
    }

    /// Prepare an auction to sell `sellAmount` that guarantees a reasonable closing price,
    /// without explicitly aiming at a particular quantity to purchase.
    /// @param sellAmount {sellTok}
    /// @return notDust Whether the prepared auction is large enough to be worth trading
    /// @return auction The prepared auction
    function prepareAuctionSell(
        IAsset sell,
        IAsset buy,
        Fix sellAmount
    ) internal view returns (bool notDust, Auction memory auction) {
        assert(sell.price().neq(FIX_ZERO) && buy.price().neq(FIX_ZERO));
        if (sellAmount.lt(dustThreshold(sell))) {
            return (false, auction);
        }

        // {UoA} = {UoA} * {1}
        Fix maxSellUoA = main.totalAssetValue().mul(main.maxAuctionSize());

        // {sellTok}
        sellAmount = fixMin(sellAmount, maxSellUoA.div(sell.price()));

        // {buyTok} = {sellTok} * {UoA/sellTok} / {UoA/buyTok}
        Fix exactBuyAmount = sellAmount.mul(sell.price()).div(buy.price());
        Fix minBuyAmount = exactBuyAmount.mul(FIX_ONE.minus(main.maxTradeSlippage()));

        // TODO Check floor() and ceil() rounding below
        return (
            true,
            Auction({
                sell: sell,
                buy: buy,
                sellAmount: sellAmount.shiftLeft(int8(sell.erc20().decimals())).floor(),
                minBuyAmount: minBuyAmount.shiftLeft(int8(buy.erc20().decimals())).ceil(),
                clearingSellAmount: 0,
                clearingBuyAmount: 0,
                externalAuctionId: 0,
                startTime: block.timestamp,
                endTime: block.timestamp + main.auctionPeriod(),
                status: AuctionStatus.NOT_YET_OPEN
            })
        );
    }

    /// Assuming we have `maxSellAmount` sell tokens avaialable, prepare an auction to
    /// cover as much of our deficit as possible, given expected trade slippage.
    /// @param maxSellAmount {sellTok}
    /// @param deficitAmount {buyTok}
    /// @return notDust Whether the prepared auction is large enough to be worth trading
    /// @return auction The prepared auction
    function prepareAuctionToCoverDeficit(
        IAsset sell,
        IAsset buy,
        Fix maxSellAmount,
        Fix deficitAmount
    ) internal view returns (bool notDust, Auction memory auction) {
        // Don't sell dust.
        if (maxSellAmount.lt(dustThreshold(sell))) {
            return (false, auction);
        }
        // Don't buy dust.
        deficitAmount = fixMax(deficitAmount, dustThreshold(buy));

        // {sellTok} = {buyTok} * {UoA/buyTok} / {UoA/sellTok}
        Fix exactSellAmount = deficitAmount.mul(buy.price()).div(sell.price());
        // exactSellAmount: Amount to sell to buy `deficitAmount` if there's no slippage

        // idealSellAmount: Amount needed to sell to buy `deficitAmount`, counting slippage
        Fix idealSellAmount = exactSellAmount.div(FIX_ONE.minus(main.maxTradeSlippage()));

        Fix sellAmount = fixMin(idealSellAmount, maxSellAmount);
        return prepareAuctionSell(sell, buy, sellAmount);
    }

    /// @return {tok} The least amount of whole tokens worth trying to sell
    function dustThreshold(IAsset asset) internal view returns (Fix) {
        // {UoA} = {UoA} * {1}
        Fix minSellUoA = main.totalAssetValue().mul(main.minRevenueAuctionSize());

        // {tok} = {UoA} / {UoA/tok}
        return minSellUoA.div(asset.price());
    }

    /// Launch an auction:
    /// - Add the auction to the local auction list
    /// - Create the auction in the external auction protocol
    /// - Emit AuctionStarted event
    /// @dev The struct must already be populated
    function launchAuction(Auction memory auction_) internal {
        auctions.push(auction_);
        Auction storage auction = auctions[auctions.length - 1];

        auction.sell.erc20().safeApprove(address(main.market()), auction.sellAmount);

        auction.externalAuctionId = main.market().initiateAuction(
            auction.sell.erc20(),
            auction.buy.erc20(),
            block.timestamp + main.auctionPeriod(),
            block.timestamp + main.auctionPeriod(),
            uint96(auction.sellAmount),
            uint96(auction.minBuyAmount),
            0,
            0,
            false,
            address(0),
            new bytes(0)
        );
        auction.status = AuctionStatus.OPEN;
        countOpenAuctions += 1;

        emit AuctionStarted(
            auctions.length - 1,
            address(auction.sell),
            address(auction.buy),
            auction.sellAmount,
            auction.minBuyAmount
        );
    }

    /// Close auctions[i]:
    /// - Set the auction status to DONE
    /// - Settle the auction in the external auction protocl
    /// - Emit AuctionEnded event
    function closeAuction(uint256 i) private {
        Auction storage auction = auctions[i];
        require(auction.status == AuctionStatus.OPEN, "can only close in-progress auctions");
        require(auction.endTime <= block.timestamp, "auction not over");

        bytes32 encodedOrder = main.market().settleAuction(auction.externalAuctionId);
        (auction.clearingSellAmount, auction.clearingBuyAmount) = decodeOrder(encodedOrder);

        auction.status = AuctionStatus.DONE;

        countOpenAuctions -= 1;

        emit AuctionEnded(
            i,
            address(auction.sell),
            address(auction.buy),
            auction.clearingSellAmount,
            auction.clearingBuyAmount
        );
    }

    /// Decode EasyAuction output into its components.
    function decodeOrder(bytes32 encodedOrder)
        private
        pure
        returns (uint256 amountSold, uint256 amountBought)
    {
        // Note: explicitly converting to a uintN truncates those bits that don't fit
        uint256 value = uint256(encodedOrder);
        amountSold = uint96(value);
        amountBought = uint96(value >> 96);
    }
}