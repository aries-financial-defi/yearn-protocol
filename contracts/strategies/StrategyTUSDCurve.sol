// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

/*import "@openzeppelinV2/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV2/contracts/math/SafeMath.sol";
import "@openzeppelinV2/contracts/utils/Address.sol";
import "@openzeppelinV2/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/curve/Curve.sol";
import "../../interfaces/uniswap/Uni.sol";

import "../../interfaces/yearn/IController.sol";
import "../../interfaces/yearn/Mintr.sol";
import "../../interfaces/yearn/Token.sol";
*/

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC20/SafeERC20.sol";

interface Uni {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;
}

interface Mintr {
    function mint(address) external;
}

interface yERC20 {
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _amount) external;
  function getPricePerFullShare() external view returns (uint);
}

interface IController {
    function withdraw(address, uint) external;
    function balanceOf(address) external view returns (uint);
    function earn(address, uint) external;
    function want(address) external view returns (address);
    function rewards() external view returns (address);
    function vaults(address) external view returns (address);
}

interface ICurveFi {

  function get_virtual_price() external view returns (uint);
  function add_liquidity( // sBTC pool
    uint256[3] calldata amounts,
    uint256 min_mint_amount
  ) external;
  function add_liquidity( // bUSD pool
    uint256[4] calldata amounts,
    uint256 min_mint_amount
  ) external;
  function remove_liquidity_imbalance(
    uint256[4] calldata amounts,
    uint256 max_burn_amount
  ) external;
  function remove_liquidity(
    uint256 _amount,
    uint256[4] calldata amounts
  ) external;
  function exchange(
    int128 from, int128 to, uint256 _from_amount, uint256 _min_to_amount
  ) external;
}

contract StrategyTUSDCurve {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    
    address constant public want = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public y = address(0xa3Aa4a71dBb17EBF2108A75b0BB7eFd9955463EF);// change yDai itoken
    address constant public ycrv = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
    address constant public yycrv = address(0x47561aADd55b829C9756CD8fE0016eCAD88dFbDC);//change yCRV Vault
    address constant public curve = address(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public ydai = address(0xa3Aa4a71dBb17EBF2108A75b0BB7eFd9955463EF);// change yDai itoken

    address constant public usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant public yusdc = address(0x82Ac4e3A35dd64dD3574bF5BD5029fd90ABc2A86);//change yUSDC itoken

    address constant public usdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address constant public yusdt = address(0x6C77dF12c39CAE90C4c46E5C19177679b7235CFa);//change yUSDT itoken

    address constant public tusd = address(0x0000000000085d4780B73119b644AE5ecd22b376);
    address constant public ytusd = address(0xe96F3621F5eF085f79Bd0Cc87b6e43378cFA6a60);//change yTUSD itoken
    

    
    address public governance;
    address public controller;
    
    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
    }
    
    function getName() external pure returns (string memory) {
        return "StrategyTUSDCurve";
    }
    
    function deposit() public {
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(y, 0);
            IERC20(want).safeApprove(y, _want);
            yERC20(y).deposit(_want);
        }
        uint _y = IERC20(y).balanceOf(address(this));
        if (_y > 0) {
            IERC20(y).safeApprove(curve, 0);
            IERC20(y).safeApprove(curve, _y);
            ICurveFi(curve).add_liquidity([0,0,0,_y],0);
        }
        uint _ycrv = IERC20(ycrv).balanceOf(address(this));
        if (_ycrv > 0) {
            IERC20(ycrv).safeApprove(yycrv, 0);
            IERC20(ycrv).safeApprove(yycrv, _ycrv);
            yERC20(yycrv).deposit(_ycrv);
        }
    }
    
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(y != address(_asset), "y");
        require(ycrv != address(_asset), "ycrv");
        require(yycrv != address(_asset), "yycrv");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }
    
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }
        
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount);
    }
    
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();
        
        
        balance = IERC20(want).balanceOf(address(this));
        
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }
    
    function withdrawTUSD(uint256 _amount) internal returns (uint) {
        IERC20(ycrv).safeApprove(curve, 0);
        IERC20(ycrv).safeApprove(curve, _amount);
        ICurveFi(curve).remove_liquidity(_amount, [uint256(0),0,0,0]);
    
        uint256 _ydai = IERC20(ydai).balanceOf(address(this));
        uint256 _yusdc = IERC20(yusdc).balanceOf(address(this));
        uint256 _yusdt = IERC20(yusdt).balanceOf(address(this));
    
        if (_ydai > 0) {
            IERC20(ydai).safeApprove(curve, 0);
            IERC20(ydai).safeApprove(curve, _ydai);
            ICurveFi(curve).exchange(0, 3, _ydai, 0);
        }
        if (_yusdc > 0) {
            IERC20(yusdc).safeApprove(curve, 0);
            IERC20(yusdc).safeApprove(curve, _yusdc);
            ICurveFi(curve).exchange(1, 3, _yusdc, 0);
        }
        if (_yusdt > 0) {
            IERC20(yusdt).safeApprove(curve, 0);
            IERC20(yusdt).safeApprove(curve, _yusdt);
            ICurveFi(curve).exchange(2, 3, _yusdt, 0);
        }
        
        uint _before = IERC20(want).balanceOf(address(this));
        yERC20(ytusd).withdraw(IERC20(ytusd).balanceOf(address(this)));
        uint _after = IERC20(want).balanceOf(address(this));
        
        return _after.sub(_before);
    }
    
    function _withdrawAll() internal {
        uint _yycrv = IERC20(yycrv).balanceOf(address(this));
        if (_yycrv > 0) {
            yERC20(yycrv).withdraw(_yycrv);
            withdrawTUSD(IERC20(ycrv).balanceOf(address(this)));
        }
    }
    
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        // calculate amount of ycrv to withdraw for amount of _want_
        uint _ycrv = _amount.mul(1e18).div(ICurveFi(curve).get_virtual_price());
        // calculate amount of yycrv to withdraw for amount of _ycrv_
        uint _yycrv = _ycrv.mul(1e18).div(yERC20(yycrv).getPricePerFullShare());
        uint _before = IERC20(ycrv).balanceOf(address(this));
        yERC20(yycrv).withdraw(_yycrv);
        uint _after = IERC20(ycrv).balanceOf(address(this));
        return withdrawTUSD(_after.sub(_before));
    }
    
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    
    function balanceOfYYCRV() public view returns (uint) {
        return IERC20(yycrv).balanceOf(address(this));
    }
    
    function balanceOfYYCRVinYCRV() public view returns (uint) {
        return balanceOfYYCRV().mul(yERC20(yycrv).getPricePerFullShare()).div(1e18);
    }
    
    function balanceOfYYCRVinyTUSD() public view returns (uint) {
        return balanceOfYYCRVinYCRV().mul(ICurveFi(curve).get_virtual_price()).div(1e18);
    }
    
    function balanceOfYCRV() public view returns (uint) {
        return IERC20(ycrv).balanceOf(address(this));
    }
    
    function balanceOfYCRVyTUSD() public view returns (uint) {
        return balanceOfYCRV().mul(ICurveFi(curve).get_virtual_price()).div(1e18);
    }
    
    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfYYCRVinyTUSD());
    }
    
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}
