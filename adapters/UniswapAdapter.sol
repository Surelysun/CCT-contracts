pragma solidity >=0.4.25 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IERC20.sol";
import "../uniswapv2/interfaces/IUniswapV2Factory.sol";
import "../uniswapv2/interfaces/IUniswapV2Router02.sol";
import "../uniswapv2/libraries/TransferHelper.sol";
import "../uniswapv2/libraries/UniswapV2Library.sol";
import "../uniswapv2/libraries/Babylonian.sol";
import "../interfaces/IExchange.sol";

contract UniswapAdapter is IExchange {
    using SafeMath for uint256;
    address constant factory = address(
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    );
    IUniswapV2Router02 constant router02 = IUniswapV2Router02(
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D)
    );

    constructor() public {}

    function weth() external override pure returns (address) {
        return router02.WETH();
    }

    function getLiquidityAddress(address tokenA, address tokenB)
        external
        override
        view
        returns (address)
    {
        return IUniswapV2Factory(factory).getPair(tokenA, tokenB);
    }

    function getLiquidity(address tokenA, address tokenB)
        external
        override
        view
        returns (uint256)
    {
        return
            IERC20(this.getLiquidityAddress(tokenA, tokenB)).balanceOf(
                msg.sender
            );
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    )
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(tokenA != tokenB, "UniswapAdapter:token cannot be same");
        IERC20(tokenA).approve(address(router02), amountA);
        IERC20(tokenB).approve(address(router02), amountB);
        return
            router02.addLiquidity(
                tokenA,
                tokenB,
                amountA,
                amountB,
                0,
                0,
                msg.sender,
                block.timestamp + 10 * 1 minutes
            );
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external override returns (uint256, uint256) {
        require(tokenA != tokenB, "UniswapAdapter:token cannot be same");
        return
            router02.removeLiquidity(
                tokenA,
                tokenB,
                liquidity,
                0,
                0,
                msg.sender,
                block.timestamp + 10 * 1 minutes
            );
    }

    function swap(
        address srcToken,
        address destToken,
        uint256 srcAmount,
        uint256 minDestAmount
    ) external override returns (uint256) {
        require(srcToken != destToken, "UniswapAdapter:token cannot be same");
        IERC20(srcToken).approve(address(router02), srcAmount);
        address[] memory path = new address[](2);
        path[0] = srcToken;
        path[1] = destToken;
        uint256[] memory amounts = router02.swapExactTokensForTokens(
            srcAmount,
            minDestAmount,
            path,
            msg.sender,
            block.timestamp + 10 * 1 minutes
        );
        return amounts[0];
    }

    //if tokenIn is weth, neet send eth to weth before call this function by:weth.deposit{value: eth value}()
    function swapTokenAndAddLiquidity(
        address tokenIn,
        address pairToken,
        uint256 amountIn
    )
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(tokenIn != pairToken, "UniswapAdapter:token cannot be same");
        return
            _swapExactTokensAndAddLiquidity(
                tokenIn,
                pairToken,
                amountIn,
                0,
                msg.sender,
                block.timestamp + 10 * 1 minutes
            );
    }

    function removeLiquidityAndSwapToToken(
        address undesiredToken,
        address desiredToken,
        uint256 liquidity
    ) external override returns (uint256) {
        return
            _removeLiquidityAndSwap(
                msg.sender,
                undesiredToken,
                desiredToken,
                liquidity,
                0,
                msg.sender,
                block.timestamp + 10 * 1 minutes
            );
    }

    // grants unlimited approval for a token to the router unless the existing allowance is high enough
    function approveRouter(address token, uint256 amount) private {
        uint256 allowance = IERC20(token).allowance(
            address(this),
            address(router02)
        );
        if (allowance < amount) {
            if (allowance > 0) {
                // clear the existing allowance
                TransferHelper.safeApprove(token, address(router02), 0);
            }
            TransferHelper.safeApprove(token, address(router02), uint256(-1));
        }
    }

    // returns the amount of token that should be swapped in such that ratio of reserves in the pair is equivalent
    // to the swapper's ratio of tokens
    // note this depends only on the number of tokens the caller wishes to swap and the current reserves of that token,
    // and not the current reserves of the other token
    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn)
        private
        pure
        returns (uint256)
    {
        return
            Babylonian
                .sqrt(
                reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))
            )
                .sub(reserveIn.mul(1997)) / 1994;
    }

    // internal function shared by the ETH/non-ETH versions
    function _swapExactTokensAndAddLiquidity(
        address tokenIn,
        address otherToken,
        uint256 amountIn,
        uint256 minOtherTokenIn,
        address to,
        uint256 deadline
    )
        private
        returns (
            uint256 amountTokenIn,
            uint256 amountTokenOther,
            uint256 liquidity
        )
    {
        // compute how much we should swap in to match the reserve ratio of tokenIn / otherToken of the pair
        uint256 swapInAmount;
        {
            (uint256 reserveIn, ) = UniswapV2Library.getReserves(
                factory,
                tokenIn,
                otherToken
            );
            swapInAmount = calculateSwapInAmount(reserveIn, amountIn);
        }
        // approve for the swap, and then later the add liquidity. total is amountIn
        approveRouter(tokenIn, swapInAmount);

        {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = otherToken;

            amountTokenOther = router02.swapExactTokensForTokens(
                swapInAmount,
                minOtherTokenIn,
                path,
                address(this),
                deadline
            )[1];
        }

        // approve the other token for the add liquidity call
        approveRouter(otherToken, amountTokenOther);
        amountTokenIn = amountIn.sub(swapInAmount);

        // no need to check that we transferred everything because minimums == total balance of this contract
        (, , liquidity) = router02.addLiquidity(
            tokenIn,
            otherToken,
            // desired amountA, amountB
            amountTokenIn,
            amountTokenOther,
            // amountTokenIn and amountTokenOther should match the ratio of reserves of tokenIn to otherToken
            // thus we do not need to constrain the minimums here
            0,
            0,
            to,
            deadline
        );
    }

    function _removeLiquidityAndSwap(
        address from,
        address undesiredToken,
        address desiredToken,
        uint256 liquidity,
        uint256 minDesiredTokenOut,
        address to,
        uint256 deadline
    ) private returns (uint256 amountDesiredTokenOut) {
        address pair = UniswapV2Library.pairFor(
            address(factory),
            undesiredToken,
            desiredToken
        );
        approveRouter(pair, liquidity);

        (uint256 amountInToSwap, uint256 amountOutToTransfer) = router02
            .removeLiquidity(
            undesiredToken,
            desiredToken,
            liquidity,
            0,
            0,
            address(this),
            deadline
        );

        address[] memory path = new address[](2);
        path[0] = undesiredToken;
        path[1] = desiredToken;
        approveRouter(undesiredToken, amountInToSwap);
        uint256 amountOutSwap = router02.swapExactTokensForTokens(
            amountInToSwap,
            minDesiredTokenOut > amountOutToTransfer
                ? minDesiredTokenOut - amountOutToTransfer
                : 0,
            path,
            to,
            deadline
        )[1];
        TransferHelper.safeTransfer(desiredToken, from, amountOutToTransfer);

        amountDesiredTokenOut = amountOutToTransfer + amountOutSwap;
    }
}
