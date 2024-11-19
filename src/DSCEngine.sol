// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    ///// ----- | State Variables | ----- /////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1; // 1 = 100% collateralized

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///// ----- | Events | ----- /////
    event CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 amountCollateral);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

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
            s_collateralTokens.push(tokenAddresses[i]);
        }
        // Set the DSC address
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///// ----- | External Functions | ----- /////
    /**
     *
     * @param tokenCollateralAddress : The address of the token to deposit as collateral
     * @param amountCollateral: The amount of the token to deposit as collateral
     * @param amountDscToMint: The amount of DSC to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Follows CEI pattern (Checks, Effects, Interactions)
     * @param tokenCollateralAddress : The address of the token to deposit as collateral
     * @param amountCollateral: The amount of the token to deposit as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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

    /**
     *
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * This function will burns DSC and redeem collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral alredy checks health factor
    }

    // In order to redeem collateral
    // 1. Health factor must be above 1 After collateral pulled out
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        // _calculateHealthFactorAfter();
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI pattern (Checks, Effects, Interactions)
     * @param amountDSCToMint The amount of decentralized stable coin to mint
     * @notice They must have more collateral value than the minumum threshold
     */
    function mintDsc(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDSCToMint;
        // If they minted too much ($150 DSC, $100 ETH) -> revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    // Do we need to check if this breaks health factor? -> No, because we are burning debt
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        s_DscMinted[msg.sender] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        // This condition is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///// ----- | Private & Internal View Functions | ----- /////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
     * @notice Returns how close to liquidation the user is
     * @notice If a user goes below 1, then they can geet liquidated
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    // 1. Check health factor (do they have enough collateral?)
    // 2. If not, revert
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///// ----- | Public & External View Functions | ----- /////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through all the collateral token, get the amount they have deposited and map it to the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        // Get the price feed for the token using the Chainlink Aggregator
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
