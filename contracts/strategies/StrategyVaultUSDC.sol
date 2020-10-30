// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

/*import "@openzeppelinV2/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV2/contracts/math/SafeMath.sol";
import "@openzeppelinV2/contracts/utils/Address.sol";
import "@openzeppelinV2/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/aave/Aave.sol";
import "../../interfaces/aave/LendingPoolAddressesProvider.sol";

import "../../interfaces/yearn/IController.sol";
import "../../interfaces/yearn/Vault.sol";
*/

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC20/SafeERC20.sol";

pragma solidity ^0.5.16;

interface IController {
    function withdraw(address, uint) external;
    function balanceOf(address) external view returns (uint);
    function earn(address, uint) external;
    function want(address) external view returns (address);
    function rewards() external view returns (address);
    function vaults(address) external view returns (address);
}

interface Vault {
    function deposit(uint) external;
    function depositAll() external;
    function withdraw(uint) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint);
}

interface LendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
    function getLendingPoolCore() external view returns (address);
    function getPriceOracle() external view returns (address);
}

interface Aave {
    function borrow(address _reserve, uint _amount, uint _interestRateModel, uint16 _referralCode) external;
    function setUserUseReserveAsCollateral(address _reserve, bool _useAsCollateral) external;
    function repay(address _reserve, uint _amount, address payable _onBehalfOf) external payable;
    function getUserAccountData(address _user)
        external
        view
        returns (
            uint totalLiquidityETH,
            uint totalCollateralETH,
            uint totalBorrowsETH,
            uint totalFeesETH,
            uint availableBorrowsETH,
            uint currentLiquidationThreshold,
            uint ltv,
            uint healthFactor
        );
    function getUserReserveData(address _reserve, address _user)
        external
        view
        returns (
            uint currentATokenBalance,
            uint currentBorrowBalance,
            uint principalBorrowBalance,
            uint borrowRateMode,
            uint borrowRate,
            uint liquidityRate,
            uint originationFee,
            uint variableBorrowIndex,
            uint lastUpdateTimestamp,
            bool usageAsCollateralEnabled
        );
}


contract StrategyVaultUSDC {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public want = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant public vault = address(0x82Ac4e3A35dd64dD3574bF5BD5029fd90ABc2A86); //change yUSDC itoken

    address public constant aave = address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8);

    address public governance;
    address public controller;

    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
    }

    function deposit() external {
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance > 0) {
            IERC20(want).safeApprove(address(vault), 0);
            IERC20(want).safeApprove(address(vault), _balance);
            Vault(vault).deposit(_balance);
        }
    }

    function getAave() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPool();
    }

    function getName() external pure returns (string memory) {
        return "StrategyVaultUSDC";
    }

    function debt() external view returns (uint) {
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(want, IController(controller).vaults(address(this)));
        return currentBorrowBalance;
    }

    function have() public view returns (uint) {
        uint _have = balanceOf();
        return _have;
    }

    function skimmable() public view returns (uint) {
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(want, IController(controller).vaults(address(this)));
        uint _have = have();
        if (_have > currentBorrowBalance) {
            return _have.sub(currentBorrowBalance);
        } else {
            return 0;
        }
    }

    function skim() external {
        uint _balance = IERC20(want).balanceOf(address(this));
        uint _amount = skimmable();
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }
        IERC20(want).safeTransfer(controller, _amount);
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(address(_asset) != address(want), "!want");
        require(address(_asset) != address(vault), "!vault");
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
        address _vault = IController(controller).vaults(address(this));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();
        balance = IERC20(want).balanceOf(address(this));
        address _vault = IController(controller).vaults(address(this));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    function _withdrawAll() internal {
        Vault(vault).withdraw(IERC20(vault).balanceOf(address(this)));
    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        uint _redeem = IERC20(vault).balanceOf(address(this)).mul(_amount).div(balanceSavingsInToken());
        uint _before = IERC20(want).balanceOf(address(this));
        Vault(vault).withdraw(_redeem);
        uint _after = IERC20(want).balanceOf(address(this));
        return _after.sub(_before);
    }

    function balanceOf() public view returns (uint) {
        return IERC20(want).balanceOf(address(this))
                .add(balanceSavingsInToken());
    }

    function balanceSavingsInToken() public view returns (uint256) {
        return IERC20(vault).balanceOf(address(this)).mul(Vault(vault).getPricePerFullShare()).div(1e18);
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
