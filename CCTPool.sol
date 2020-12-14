pragma solidity >=0.4.25 <0.8.0;
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IControl.sol";
import "./interfaces/IExchange.sol";
import "./uniswapv2/libraries/TransferHelper.sol";

pragma experimental ABIEncoderV2;

contract CCTPool {
    struct Follower {
        // address followerAddress; // 地址
        uint256 investAmount; // money
        uint256 withdrawnAmount;
        uint256 atTime;
        bool isInvested;
    }
    struct PoolInfo {
        address master; // 基金创始人地址
        // string title;
        // string tags;
        uint256 goal;
        uint256 hardTop;
        uint256 startTime;
        uint256 duration;
        address acceptToken;
        address[] targetTokens;
        uint32 expectedEarningRate; //预期收益率
        uint8 managerShareRate; //基金管理员的分成比例。固定比例，有上下限
        uint8 maxRetracement; //回撤
        // string introduction;
        uint256 totalCollectedAmount; // 当前募集金额
        uint256 totalBalanceAmount; // 当前结存总额
        int64 actualEarningRate;
        bool isServiceEnd; //管理员已经结算过
        bool isSettled; //平台方已经结算过
        uint256 createTime;
    }
    struct AssetInfo {
        address addr;
        uint256 balance;
    }
    uint256 public poolId;
    PoolInfo poolInfo;
    uint256 public totalFollowers;
    uint256 totalWithdrawals; //总共提走币的人
    mapping(address => Follower) public followerMap; // 跟随者列表
    // address[] invests; // 购买列表
    uint256 locked;
    //平台抽成比例
    uint8 public serviceShareRate = 10;
    IControl private control;
    string public version = "0.1";

    event PoolInvested(uint256 id, address from, uint256 value);
    event SwapToken(uint256 id, uint256 amount);

    constructor(
        uint256 id,
        address creator,
        address acceptTokenAddress,
        address[] memory targetTokensArray,
        uint256 goal,
        uint256 hardTop,
        uint256 startTime,
        uint256 duration,
        uint32 expectedEarningRate,
        uint8 managerShareRate,
        uint8 maxRetracement
    ) public {
        require(
            acceptTokenAddress != address(0),
            "CCTPool: accept token must be not the zero address"
        );
        require(
            targetTokensArray.length != 0,
            "CCTPool: target tokens is none"
        );
        for (uint256 i = 0; i < targetTokensArray.length; i++) {
            require(
                targetTokensArray[i] != address(0),
                "CCTPool: accept token must be not the zero address"
            );
        }
        require(goal >= 1, "At least 1");
        require(hardTop >= goal, "HardTop must great than goal");
        require(
            startTime > block.timestamp,
            "StartTime must great current time"
        );
        require(
            expectedEarningRate >= 10,
            "Expected earning rate must great than 10%"
        );
        require(
            managerShareRate + serviceShareRate <= 100,
            "Total rate must less than 100%"
        );
        require(maxRetracement >= 30, "Max retracement at least 30%");
        require(duration > 0, "At least 1 day");

        control = IControl(msg.sender);
        poolId = id;
        poolInfo = PoolInfo({
            master: creator,
            goal: goal,
            hardTop: hardTop,
            startTime: startTime,
            duration: duration,
            acceptToken: acceptTokenAddress,
            targetTokens: targetTokensArray,
            expectedEarningRate: expectedEarningRate,
            managerShareRate: managerShareRate,
            maxRetracement: maxRetracement,
            totalCollectedAmount: 0,
            totalBalanceAmount: 0,
            actualEarningRate: 0,
            isServiceEnd: false,
            isSettled: false,
            createTime: block.timestamp
        });
        // poolInfo = info;
    }

    receive() external payable {
        require(
            msg.sender == address(control.uniswapExchange().weth()),
            "CCTPool: must from weth"
        );
    }

    modifier lock() {
        require(locked == 0, "Locked, please waiting for a while");
        locked = 1;
        _;
        locked = 0;
    }

    modifier onlyMaster() {
        require(isMaster(), "Only owner");
        _;
    }

    modifier onlyControl() {
        require(isControl(), "Only control");
        _;
    }

    modifier inPreparation() {
        require(isEarlyTime(), "Expired");
        require(
            poolInfo.totalCollectedAmount <= poolInfo.hardTop,
            "Has reached goal"
        );
        _;
    }

    // modifier inRunning(uint256 id) {
    //     uint256 i1;
    //     uint256 i2;
    //     bool b1;
    //     (i1, i2, b1) = isRunningTime(id);
    //     uint256 j1;
    //     uint256 j2;
    //     bool b2;
    //     (j1, j2, b2) = isGoalAchieved(id);
    //     require(b1, "ContractCapital: NOT RIGHT TIME");
    //     require(b2, "ContractCapital: NOT ENOUGH TOKEN");
    //     _;
    // }

    modifier inService() {
        require(poolInfo.isServiceEnd, "Service end");
        _;
    }

    // modifier canSettle(uint256 id) {
    //     require(isEndedTime(id), "ContractCapital: NOT END");
    //     require(isGoalAchieved(id), "ContractCapital: NOT RUN");
    //     _;
    // }

    function isControl() public view returns (bool) {
        return msg.sender == control.admin();
    }

    function isMaster() public view returns (bool) {
        return msg.sender == poolInfo.master;
    }

    function isEarlyTime() public view returns (bool) {
        return poolInfo.startTime >= block.timestamp;
    }

    function getBlockTime() public view returns (uint256) {
        return block.timestamp;
    }

    function isRunningTime() public view returns (bool) {
        return (poolInfo.startTime <= block.timestamp &&
            block.timestamp <
            poolInfo.startTime + poolInfo.duration * 1 minutes);
    }

    function isEndedTime() public view returns (bool) {
        return (poolInfo.startTime + poolInfo.duration * 1 minutes <=
            block.timestamp);
    }

    function isGoalAchieved() public view returns (bool) {
        return (poolInfo.goal <= poolInfo.totalCollectedAmount);
    }

    // function getInvestedAmount() external view returns (uint256) {
    //     return followerMap[msg.sender].investAmount;
    // }

    // function getPools() external view returns (PoolInfo[] memory) {
    //     uint256 total = poolCount;
    //     PoolInfo[] memory pools;
    //     for (uint256 index = 0; index < total; index++) {
    //         pools[index] = poolList[index].poolInfo;
    //     }
    //     return pools;
    // }

    function getPoolState()
        external
        view
        returns (
            PoolInfo memory,
            Follower memory,
            uint256
        )
    {
        return (poolInfo, followerMap[msg.sender], calcBalance());
    }

    // function getBalance(address addr) private returns (uint256) {
    //     if (addr == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
    //         return address(this).balance;
    //     }
    //     return IERC20(addr).balanceOf(address(this));
    // }

    // function getAssets() external returns (AssetInfo[] memory) {
    //     AssetInfo[] memory assets;
    //     assets[0] = AssetInfo({
    //         addr: poolInfo.acceptToken,
    //         balance: getBalance(poolInfo.acceptToken)
    //     });
    //     for (uint256 i = 0; i < poolInfo.targetTokens.length; i++) {
    //         assets[i + 1] = AssetInfo({
    //             addr: poolInfo.targetTokens[i],
    //             balance: getBalance(poolInfo.targetTokens[i])
    //         });
    //     }
    //     return assets;
    // }

    // function getPoolState2() external view returns (follower memory) {
    //     follower memory f = followerMap[msg.sender];
    //     return f;
    // }

    function investToPool(uint256 amountIn)
        external
        payable
        lock()
        inPreparation()
    {
        // require(IERC20(acceptToken).approve(address(this), amountIn), 'approve failed.');
        if (
            poolInfo.acceptToken ==
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            amountIn = msg.value;
        }
        require(amountIn > 0, "No zero");
        uint256 totalAmount = poolInfo.totalCollectedAmount + amountIn;
        require(totalAmount <= poolInfo.hardTop, "Overflow");
        // require(
        //     IERC20(acceptToken).transferFrom(
        //         msg.sender,
        //         address(this),
        //         amountIn
        //     ),
        //     "transferFrom failed."
        // );
        // require(
        //     transferFrom(
        //         msg.sender,
        //         address(this),
        //         amountIn
        //     ),
        //     "transferFrom failed."
        // );
        //eth
        if (
            poolInfo.acceptToken !=
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            TransferHelper.safeTransferFrom(
                poolInfo.acceptToken,
                msg.sender,
                address(this),
                amountIn
            );
        }

        if (!followerMap[msg.sender].isInvested) {
            totalFollowers++;
            followerMap[msg.sender] = Follower({
                investAmount: amountIn,
                withdrawnAmount: 0,
                atTime: block.timestamp,
                isInvested: true
            });
        } else {
            followerMap[msg.sender].investAmount += amountIn;
        }
        poolInfo.totalCollectedAmount = totalAmount;
        emit PoolInvested(poolId, msg.sender, amountIn);
    }

    function depositEth(address token, uint256 amount) private {
        if (token == control.uniswapExchange().weth()) {
            IWETH(token).deposit{value: amount}();
        }
    }

    function withdrawEth(address token, uint256 amount) private {
        if (token == control.uniswapExchange().weth()) {
            IWETH(token).withdraw(amount);
        }
    }

    //check token is in allowable list
    function isValidSubject(address token) private view returns (bool) {
        for (uint256 i = 0; i < poolInfo.targetTokens.length; i++) {
            if (token == poolInfo.targetTokens[i]) {
                return true;
            }
        }
        address t = token;
        if (
            poolInfo.acceptToken ==
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ) {
            t = control.uniswapExchange().weth();
        }
        return t == token;
    }

    function getLiquidity(address tokenA, address tokenB)
        external
        view
        returns (uint256)
    {
        return control.uniswapExchange().getLiquidity(tokenA, tokenB);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    )
        external
        onlyMaster
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(
            isValidSubject(tokenA) && isValidSubject(tokenB),
            "CCTPool: invalid subject"
        );

        depositEth(tokenA, amountA);
        depositEth(tokenB, amountB);
        TransferHelper.safeTransfer(
            tokenA,
            address(control.uniswapExchange()),
            amountA
        );
        TransferHelper.safeTransfer(
            tokenB,
            address(control.uniswapExchange()),
            amountB
        );
        return
            control.uniswapExchange().addLiquidity(
                tokenA,
                tokenB,
                amountA,
                amountB
            );
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external onlyMaster returns (uint256, uint256) {
        address pair = control.uniswapExchange().getLiquidityAddress(
            tokenA,
            tokenB
        );
        TransferHelper.safeTransfer(
            pair,
            address(control.uniswapExchange()),
            liquidity
        );
        uint256 amountA;
        uint256 amountB;
        (amountA, amountB) = control.uniswapExchange().removeLiquidity(
            tokenA,
            tokenB,
            liquidity
        );
        withdrawEth(tokenA, amountA);
        withdrawEth(tokenB, amountB);
        return (amountA, amountB);
    }

    function swap(
        address srcToken,
        address destToken,
        uint256 srcAmount,
        uint256 minDestAmount
    ) external onlyMaster returns (uint256) {
        require(isValidSubject(destToken), "CCTPool: invalid subject");
        depositEth(srcToken, srcAmount);
        TransferHelper.safeTransfer(
            srcToken,
            address(control.uniswapExchange()),
            srcAmount
        );
        uint256 amount = control.uniswapExchange().swap(
            srcToken,
            destToken,
            srcAmount,
            minDestAmount
        );
        withdrawEth(destToken, srcAmount);
        SwapToken(poolId, amount);
        return amount;
    }

    //if tokenIn is weth, neet send eth to weth before call this function by:weth.deposit{value: eth value}()
    function swapTokensAndAddLiquidity(
        address tokenIn,
        address pairToken,
        uint256 amountIn
    )
        external
        onlyMaster
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(isValidSubject(pairToken), "CCTPool: invalid subject");
        depositEth(tokenIn, amountIn);
        TransferHelper.safeTransfer(
            tokenIn,
            address(control.uniswapExchange()),
            amountIn
        );
        return
            control.uniswapExchange().swapTokenAndAddLiquidity(
                tokenIn,
                pairToken,
                amountIn
            );
    }

    function removeLiquidityAndSwapToToken(
        address undesiredToken,
        address desiredToken,
        uint256 liquidity
    ) external onlyMaster returns (uint256) {
        address pair = control.uniswapExchange().getLiquidityAddress(
            undesiredToken,
            desiredToken
        );
        TransferHelper.safeTransfer(
            pair,
            address(control.uniswapExchange()),
            liquidity
        );
        uint256 amountDesiredTokenOut = control
            .uniswapExchange()
            .removeLiquidityAndSwapToToken(
            undesiredToken,
            desiredToken,
            liquidity
        );
        withdrawEth(desiredToken, amountDesiredTokenOut);
        return amountDesiredTokenOut;
    }

    /**
     *清算
     */
    function liquidate() external {}

    function setEarningRate(uint256 currentBalance) external {
        poolInfo.totalBalanceAmount = currentBalance;
        poolInfo.actualEarningRate = int32(
            ((currentBalance - poolInfo.totalCollectedAmount) * 100) /
                poolInfo.totalCollectedAmount
        );
    }

    // function getFollower(address addr) private view returns (uint256, bool) {
    //     for (uint256 i = 0; i < totalFollowers; i++) {
    //         if (followerMap[i].followerAddress == addr) {
    //             // f = followerMap[i];
    //             // has = true;
    //             return (i, true);
    //         }
    //     }
    //     return (0, false);
    // }

    function calcBalance() public view returns (uint256) {
        if (isEarlyTime()) {
            return 0;
        }
        if (isRunningTime() && isGoalAchieved()) {
            return 0;
        }

        uint256 investAmount = followerMap[msg.sender].investAmount;
        if (isMaster()) {
            if (poolInfo.isServiceEnd) {
                return 0;
            }
        } else if (isControl()) {
            if (poolInfo.isSettled) {
                return 0;
            }
        } else if (
            investAmount == 0 ||
            investAmount == followerMap[msg.sender].withdrawnAmount
        ) {
            return 0;
        }
        uint256 returnMoney;
        if (!isGoalAchieved()) {
            returnMoney = investAmount;
        } else {
            uint256 total = poolInfo.totalBalanceAmount;
            if (total == 0) {
                total = poolInfo.totalCollectedAmount;
            }
            if (poolInfo.actualEarningRate < poolInfo.expectedEarningRate) {
                returnMoney =
                    (total * investAmount) /
                    poolInfo.totalCollectedAmount;
            } else {
                uint256 remained = 100 -
                    poolInfo.managerShareRate -
                    serviceShareRate;
                uint256 profit = total - poolInfo.totalCollectedAmount;
                returnMoney =
                    investAmount +
                    (profit * remained * investAmount) /
                    100 /
                    poolInfo.totalCollectedAmount;
                if (isMaster()) {
                    returnMoney += (profit * poolInfo.managerShareRate) / 100;
                } else if (isControl()) {
                    returnMoney += (profit * serviceShareRate) / 100;
                }
            }
        }
        return returnMoney;
    }

    /**
     *   参与投资的人以及管理员执行资金赎回
     */
    function redeem() external {
        uint256 returnMoney = calcBalance();
        require(returnMoney != 0, "balance 0");
        if (isMaster()) {
            poolInfo.isServiceEnd = true;
        } else if (isControl()) {
            poolInfo.isSettled = true;
        }
        followerMap[msg.sender].withdrawnAmount = followerMap[msg.sender]
            .investAmount;
        msg.sender.transfer(returnMoney);
    }

    /**
     *平台执行服务结算
     */
    // function settleService(uint256 id)
    //     external
    //     payable
    //     onlyControl
    //     exist(id)
    //     inService(id)
    //     canSettle(id)
    // {
    //     Pool memory p = poolList[id];
    //     PoolInfo memory info = p.poolInfo;
    //     if (info.actualEarningRate >= info.expectedEarningRate) {
    //         uint256 profit = p.totalBalanceAmount - info.totalCollectedAmount;
    //         uint256 returnMoney = profit * serviceShareRate;
    //         msg.sender.transfer(returnMoney);
    //     }
    //     info.isServiceEnd = true;
    // }

    // function batchTransferToken(
    //     address _token,
    //     address[] _receivers,
    //     uint256[] _tokenAmounts
    // ) public checkArrayArgument(_receivers, _tokenAmounts) {}
}
