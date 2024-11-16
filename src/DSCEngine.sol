// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * @title DSCEngine
 * @author Andrea De Blasio
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain
 * a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmic Stable
 *
 * It is similar to DAI if DAI has no governance, no fees, and was only backeed by
 * wETH and wBTC
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all the collateral <= the $ backed value of all the DSC.
 *
 * @notice This contracts is the core of the DSC System. It handles all the logic for minting
 * and redeeminng DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDao DSS (DAI) system.
 *
 * // Thresholds to let's say 150%
 *     // $100 ETH Collateral -> $74
 *     // $50 DSC
 *     // UNDERCOLLATERALIZED!
 *
 *     // I'll pay back $50 DSC -> Get all your collateral!
 *     // $74 ETH
 *     // -$50 DSC
 *     // $24
 */

contract DSCEngine is ReentrancyGuard {
    ///// ----- | Errors | ----- /////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();

    ///// ----- | State Variables | ----- /////
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    DecentralizedStableCoin private immutable i_dsc;

    ///// ----- | Events | ----- /////
    event CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 amountCollateral);

    ///// ----- | Modifiers | ----- /////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///// ----- | Functions | ----- /////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // Set the price feed for the token
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        // Set the DSC address
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///// ----- | External Functions | ----- /////
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice Follows CEI pattern (Checks, Effects, Interactions)
     * @param tokenCollateralAddress : The address of the token to deposit as collateral
     * @param amountCollateral: The amount of the token to deposit as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
