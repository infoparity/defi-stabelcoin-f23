// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedBurnDSC} from "../mocks/MockFailedBurnDSC.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStablecoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant AMOUNT_TO_BREAK_HF_MINT = 10001 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();
        _;
    }
    
    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor();

        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_TO_COVER);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    ///////////////////////////
    // CONSTRUCTOR TESTS
    ///////////////////////////
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////////
    // Price Tests
    //////////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //////////////////////////
    // Deposit Collateral Tests
    //////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    function testCanDepositCollateralEmitEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, false, false);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralWithoutMinting()
        public
        depositedCollateral
    {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testRevertIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(USER, AMOUNT_COLLATERAL);
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockEngine));
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(
            address(mockEngine),
            AMOUNT_COLLATERAL
        );
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////////////
    // DEPOSIT AND MINT DSC TESTS
    /////////////////////////
    function testCanDepositAndMintDSC() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    function testRevertsIfMintDscBreaksHealthFactor() public {
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL *
            (uint256(price) * engine.getAdditionalFeedPrecision())) /
            engine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(
            amountToMint,
            engine.getUsdValue(weth, AMOUNT_COLLATERAL)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
    }

    ////////////////////////
    // MINT DSC TESTS
    ////////////////////////

    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor()
        public
        depositedCollateral
    {
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = ((AMOUNT_COLLATERAL *
            (uint256(price) * engine.getAdditionalFeedPrecision())) /
            engine.getPrecision());
        uint256 expectedHealthFactor = engine.calculateHealthFactor(
            amountToMint,
            engine.getUsdValue(weth, AMOUNT_COLLATERAL)
        );
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testIfMintStoresDsc() public depositedCollateralAndMintedDsc {
        uint256 expectedDscMinted = AMOUNT_TO_MINT;
        (uint256 totalDscMinted, ) = engine.getAccountInformation(USER);
        assertEq(expectedDscMinted, totalDscMinted);
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        engine.mintDsc(AMOUNT_TO_MINT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    function testRevertsIfMintFails() public {
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockEngine));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockEngine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();
    }

    ////////////////////////
    // REDEEM COLLATERAL TESTS
    ////////////////////////
    function testRevertIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testIfRedeemCollateralEmitsEvent() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false);
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        vm.stopPrank();
        assertEq(userBalance, AMOUNT_COLLATERAL);
    }

    function testRevertIfRedeemTransferFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(USER, AMOUNT_COLLATERAL);
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockEngine));
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(
            address(mockEngine),
            AMOUNT_COLLATERAL
        );
        mockEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////
    // REDEEM COLLATERAL FOR DSC TESTS
    ////////////////////////
    function testRevertIfRedeemForDscIsZero()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, 0, AMOUNT_TO_MINT);
        vm.stopPrank();
    }
    
    ////////////////////////
    // BURN DSC
    ////////////////////////
    
    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        uint256 startingUserBalance = dsc.balanceOf(USER);
        uint256 expectedStartingUserbalance = AMOUNT_TO_MINT;
        uint256 expectedEndingUserBalance = 0;
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDsc(AMOUNT_TO_MINT);
        uint256 endingUserBalance = dsc.balanceOf(USER);
        vm.stopPrank();
        assertEq(startingUserBalance, expectedStartingUserbalance);
        assertEq(endingUserBalance, expectedEndingUserBalance);
    }
    
    function testRevertIfBurnIsZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }
    
   function testCantBurnMoreThanUserHas() public {
    vm.prank(USER);
    vm.expectRevert();
    engine.burnDsc(AMOUNT_TO_MINT);
   } 

    //////////////////////////
    // LIQUIDATE
    //////////////////////////
    function testMustImproveHealthFactorOnLiquidation() public {
       MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
       tokenAddresses = [weth];
       priceFeedAddresses = [ethUsdPriceFeed];
       address owner = msg.sender;
       vm.prank(owner);
       DSCEngine mockEngine = new DSCEngine(
           tokenAddresses,
           priceFeedAddresses,
           address(mockDsc)
       );
       mockDsc.transferOwnership(address(mockEngine));
       vm.startPrank(USER);
       ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
       mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
       vm.stopPrank();

       ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

       vm.startPrank(LIQUIDATOR);
       ERC20Mock(weth).approve(address(mockEngine), COLLATERAL_TO_COVER);
       uint256 debtToCover = 1 ether;
       mockEngine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
       mockDsc.approve(address(mockEngine), debtToCover);
       int256 ethUsdUpdatePrice = 18e8;
       MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatePrice);
       vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
       mockEngine.liquidate(weth, USER, debtToCover);
       vm.stopPrank();
    }
    
    function testRevertIfHealthFactorOkOnLiquidation() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_TO_COVER);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }
    
    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) + (engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) / engine.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110; 
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }
    
    function testLiquidatorTakesOnUserDebt() public liquidated {
        (uint256 liquidatorDscMinted, ) = engine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }
    
    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted, ) = engine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }
    
    function testUserHasCollateralAfterLiquidation() public liquidated {
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) + (engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) / engine.getLiquidationBonus());
        
        uint256 usdAmountLiquidated = engine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL) - usdAmountLiquidated;
        (, uint256 userCollateralInUsd) = engine.getAccountInformation(USER);
        uint256 hardCodedExpectedValue = 70000000000000000020;
        assertEq(userCollateralInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralInUsd, hardCodedExpectedValue);
    }
    
    ///////////////////////////
    // VIEW AND PURE FUNCTIONS
    ///////////////////////////
    function testGetAccountInformation() public depositedCollateralAndMintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_TO_MINT);
        assertEq(collateralValueInUsd, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
    }
    
    function testAdditionalFeedPrecision() public {
        uint256 expectedPrecision = engine.getAdditionalFeedPrecision();
        assertEq(expectedPrecision, engine.getAdditionalFeedPrecision());
    }
    
    function testGetPrecision() public {
        uint256 expectedPrecision = engine.getPrecision();
        assertEq(expectedPrecision, engine.getPrecision());
    }
    
    function testGetLiquidationBonus() public {
        uint256 expectedBonus = engine.getLiquidationBonus();
        assertEq(expectedBonus, engine.getLiquidationBonus());
    }
    
    function testCalculateHealthFactor() public {
        uint256 expectedHealthFactor = engine.calculateHealthFactor(10, 100);
        assertEq(expectedHealthFactor, engine.calculateHealthFactor(10, 100));
    }
}
