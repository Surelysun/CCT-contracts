pragma solidity >=0.5.0;

interface IExchange {
    function weth() external pure returns (address);

    function getLiquidityAddress(address _tokenA, address _tokenB)
        external
        view
        returns (address);

    function getLiquidity(address _tokenA, address _tokenB)
        external
        view
        returns (uint256);

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity
    ) external returns (uint256 amountA, uint256 amountB);

    function swap(
        address _srcToken,
        address _destToken,
        uint256 _srcAmount,
        uint256 _minDestAmount
    ) external returns (uint256);

    function swapTokenAndAddLiquidity(
        address _tokenIn,
        address _pairToken,
        uint256 _amountIn
    )
        external
        returns (
            uint256 amountTokenIn,
            uint256 amountTokenOther,
            uint256 liquidity
        );

    function removeLiquidityAndSwapToToken(
        address _undesiredToken,
        address _desiredToken,
        uint256 _liquidity
    ) external returns (uint256 amountDesiredTokenOut);
}
