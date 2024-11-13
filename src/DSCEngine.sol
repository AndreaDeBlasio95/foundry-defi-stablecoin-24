// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

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
contract DSCEngine {
    function depositCollateralAndMintDsc() external {}

    function depositCollateral() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
