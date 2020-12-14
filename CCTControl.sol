pragma solidity >=0.4.25 <0.8.0;
import "./interfaces/IExchange.sol";
import "./CCTPool.sol";
import "./adapters/UniswapAdapter.sol";

contract CCTControl is IControl {
    address public override admin;
    IExchange public override uniswapExchange;
    mapping(uint256 => address) public poolList;
    uint256 public poolCount;
    event PoolCreated(uint256 poolId, address indexed poolAddress);
    event AdminTransferred(
        address indexed previousAdmin,
        address indexed newAdmin
    );

    constructor() public {
        admin = msg.sender;
        uniswapExchange = new UniswapAdapter();
    }

    modifier exist(uint256 id) {
        require(poolList[id] != address(0), "CCTControl:not exist");
        _;
    }
    modifier onlyAdmin() {
        require(admin == msg.sender, "CCTControl: caller is not admin");
        _;
    }

    function newPool(
        uint256 id,
        address acceptTokenAddress,
        address[] memory targetTokensArray,
        uint256 goal,
        uint256 hardTop,
        uint256 startTime,
        uint256 duration,
        uint32 expectedEarningRate,
        uint8 managerShareRate,
        uint8 maxRetracement
    ) external {
        require(poolList[id] == address(0), "CCTControl: pool already exist");
        CCTPool pool = new CCTPool(
            id,
            msg.sender,
            acceptTokenAddress,
            targetTokensArray,
            goal,
            hardTop,
            startTime,
            duration,
            expectedEarningRate,
            managerShareRate,
            maxRetracement
        );
        poolCount++;
        poolList[id] = address(pool);
        emit PoolCreated(id, address(pool));
    }

    // function getPoolInfo(uint256 id) external returns (address) {
    //     return poolList[id];
    // }

    function transferAdmin(address _admin) external onlyAdmin {
        require(
            _admin != address(0),
            "CCTControl: new admin must be not the zero address"
        );
        emit AdminTransferred(admin, _admin);
        admin = _admin;
    }

    // function calcBalance(uint256 id)
    //     external
    //     view
    //     exist(id)
    //     onlyAdmin
    //     returns (uint256)
    // {
    //     return poolList[poolCount].calcBalance();
    // }

    // function redeem(uint256 id) external exist(id) onlyAdmin {
    //     poolList[poolCount].redeem();
    // }
}
