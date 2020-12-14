pragma solidity >=0.5.0;
import "./IExchange.sol";

interface IControl {
    function uniswapExchange() external view returns (IExchange);

    function admin() external view returns (address);
}
