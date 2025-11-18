// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {IGoldToken} from "../src/interfaces/IGoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {GoldReference} from "./utils/GoldReference.sol";
import {ContractThatRejectsEth} from "./mock/ContractThatRejectsEth.sol";

contract GoldTokenTest is Test {
    GoldToken public goldToken;
    address[] public signers;

    MockV3Aggregator public goldAggregator;
    MockV3Aggregator public ethAggregator;

    struct MintScenario {
        uint96 ethAmount;
        int256 goldUsdPerTroyOunce;
        int256 ethUsd;
    }

    MintScenario[] public fixtureMintScenario;

    address internal constant DEFAULT_LOTTERIE = address(10);
    address internal constant TABLE_LOTTERIE = address(0xBEEF);
    address internal constant TABLE_FEES = address(0xFEE);
    address internal defaultFeesAddress;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    function setUp() public {
        uint256 id;
        assembly {
            id := chainid()
        }
        if (id == 31337) {
            // Local network
            goldAggregator = new MockV3Aggregator(8, int256(100000000000)); // 100.00 USD
            ethAggregator = new MockV3Aggregator(8, int256(50000000000)); // 50.00 USD
        } else {
            // Mainnet fork
            goldAggregator = MockV3Aggregator(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6); // gold / USD
            ethAggregator = MockV3Aggregator(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // ETH / USD
        }

        signers = [address(0x1), address(0x2), address(0x3)];
        vm.deal(signers[0], 10 ether);

        GoldToken implementation = new GoldToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                GoldToken.initialize.selector, address(this), address(goldAggregator), address(ethAggregator)
            )
        );
        goldToken = GoldToken(address(proxy));
        goldToken.setLotterieAddress(DEFAULT_LOTTERIE);
        defaultFeesAddress = goldToken.getFeesAddress();

        fixtureMintScenario.push(
            MintScenario({ethAmount: 1 ether, goldUsdPerTroyOunce: int256(1_200 * 1e8), ethUsd: int256(1_800 * 1e8)})
        );

        fixtureMintScenario.push(
            MintScenario({ethAmount: 0.01 ether, goldUsdPerTroyOunce: int256(900 * 1e8), ethUsd: int256(1_600 * 1e8)})
        );

        fixtureMintScenario.push(
            MintScenario({
                ethAmount: 1_000 ether, goldUsdPerTroyOunce: int256(1_950 * 1e8), ethUsd: int256(1_900 * 1e8)
            })
        );

        fixtureMintScenario.push(
            MintScenario({ethAmount: 2 ether, goldUsdPerTroyOunce: int256(1_234 * 1e8), ethUsd: int256(1_230 * 1e8)})
        );
    }

    function test_addOwner() public {
        goldToken.addOwner(signers[0]);
        bool isOwner = goldToken.hasOwnerRole(signers[0]);
        assertTrue(isOwner, "signers[0] does not have OWNER_ROLE");
    }

    function test_removeOwner() public {
        goldToken.removeOwner(signers[0]);
        bool isOwner = goldToken.hasOwnerRole(signers[0]);
        assertFalse(isOwner, "signers[0] have OWNER_ROLE");
    }

    function test_pause() public {
        goldToken.pause();

        vm.expectRevert();
        goldToken.mint();

        vm.expectRevert();
        goldToken.burn(0);

        goldToken.unpause();
        bool isPaused = goldToken.paused();
        assertFalse(isPaused, "contract should be not paused");
    }

    function test_setFeesAddress() public {
        address feesAddress = goldToken.getFeesAddress();
        assertEq(feesAddress, address(this));

        goldToken.setFeesAddress(address(signers[0]));

        feesAddress = goldToken.getFeesAddress();
        assertEq(feesAddress, address(signers[0]));
    }

    /// @notice Table-driven test for various mint scenarios. Check https://getfoundry.sh/forge/advanced-testing/table-testing/ for more details.
    function tableMintScenario(MintScenario memory mintScenario) public {
        goldToken.setLotterieAddress(TABLE_LOTTERIE);
        goldToken.setFeesAddress(TABLE_FEES);

        goldAggregator.updateAnswer(mintScenario.goldUsdPerTroyOunce);
        ethAggregator.updateAnswer(mintScenario.ethUsd);

        vm.deal(address(this), mintScenario.ethAmount);

        (uint256 expectedUser, uint256 expectedLotterie, uint256 expectedFees) = GoldReference.calcMintBreakdown(
            mintScenario.ethAmount, mintScenario.goldUsdPerTroyOunce, mintScenario.ethUsd
        );

        uint256 userBefore = goldToken.balanceOf(address(this));
        uint256 lotterieBefore = goldToken.balanceOf(TABLE_LOTTERIE);
        uint256 feesBefore = goldToken.balanceOf(TABLE_FEES);

        goldToken.mint{value: mintScenario.ethAmount}();

        assertEq(goldToken.balanceOf(address(this)) - userBefore, expectedUser, "user mint mismatch");
        assertEq(goldToken.balanceOf(TABLE_LOTTERIE) - lotterieBefore, expectedLotterie, "lotterie mismatch");
        assertEq(goldToken.balanceOf(TABLE_FEES) - feesBefore, expectedFees, "fees mismatch");

        goldToken.setLotterieAddress(DEFAULT_LOTTERIE);
        goldToken.setFeesAddress(defaultFeesAddress);
    }

    function test_getFees() public view {
        uint256 fees = goldToken.getFees();
        assertEq(fees, uint256(5));
    }

    function test_mintValueZero() public {
        vm.expectRevert(IGoldToken.ValueMustBeGreaterThanZero.selector);
        goldToken.mint{value: 0}();
    }

    function test_mint() public {
        vm.startPrank(signers[0]);
        uint256 contractBefore = address(goldToken).balance;
        goldToken.mint{value: 1 ether}();
        uint256 balance = goldToken.balanceOf(address(signers[0]));
        assertTrue(balance > 0);
        uint256 contractBalance = address(goldToken).balance;
        assertEq(contractBalance, contractBefore + 1 ether);
        vm.stopPrank();
    }

    function test_burn() public {
        goldToken.mint{value: 10000}();
        uint256 balance = goldToken.balanceOf(address(signers[0]));
        goldToken.burn(balance);
        balance = goldToken.balanceOf(address(signers[0]));
        assertEq(balance, 0);
    }

    function test_transfer() public {
        goldToken.mint{value: 10000}(); // Receive 5000 GLD
        bool success = goldToken.transfer(address(signers[0]), 1000);
        assertTrue(success, "transfer should succeed");
        uint256 balance = goldToken.balanceOf(address(this));
        assertTrue(balance > 0);
    }

    function test_transferAmountZero() public {
        goldToken.mint{value: 10000}(); // Receive 5000 GLD
        vm.expectRevert(IGoldToken.AmountMustBeGreaterThanZero.selector);
        // transfer returns a value but this call reverts before the response is produced
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        goldToken.transfer(address(signers[0]), 0);
    }

    function test_claimEth() public {
        vm.deal(address(this), 1 ether);
        uint256 ownerBalanceBefore = address(this).balance;
        uint256 depositAmount = 0.25 ether;
        goldToken.mint{value: depositAmount}();
        assertEq(address(goldToken).balance, depositAmount, "contract should hold deposited ETH");

        goldToken.claimEth();

        assertEq(address(goldToken).balance, 0, "contract balance should be zero after withdrawal");
        assertEq(address(this).balance, ownerBalanceBefore, "owner should recover the deposited ETH");
    }

    function test_claimEth_reverts_on_failed_transfer() public {
        ContractThatRejectsEth reverter = new ContractThatRejectsEth();
        goldToken.addOwner(address(reverter));

        vm.deal(address(this), 1 ether);
        goldToken.mint{value: 0.1 ether}();
        assertEq(address(goldToken).balance, 0.1 ether, "contract should hold deposited ETH");

        vm.expectRevert(IGoldToken.EthTransferFailed.selector);
        reverter.claimGoldTokenEth(goldToken);
    }

    function test_getUsers() public {
        goldToken.mint{value: 10000}();
        address[] memory users = goldToken.getUsers();
        assertEq(users.length, 1);
        assertEq(users[0], address(this));
    }

    function test_getTimestamps() public {
        goldToken.mint{value: 10000}();
        (address[] memory users, uint256[] memory timestamps) = goldToken.getTimestamps();
        assertEq(users.length, 1);
        assertEq(users[0], address(this));
        assertEq(timestamps.length, 1);
        assertEq(timestamps[0], block.timestamp);
    }

    function test_getGoldPriceInEth() public view {
        int256 expected = _expectedGoldPriceInEth(100000000000, 50000000000);
        assertEq(goldToken.getGoldPriceInEth(), expected);
    }

    function test_getGoldPriceInEth_reactsToFeedUpdates() public {
        goldAggregator.updateAnswer(int256(180000000000)); // 1800 USD per troy ounce
        ethAggregator.updateAnswer(int256(200000000000)); // 2000 USD per ETH

        int256 expected = _expectedGoldPriceInEth(180000000000, 200000000000);
        assertEq(goldToken.getGoldPriceInEth(), expected);
    }

    function _expectedGoldPriceInEth(int256 goldUsdPerTroyOunce, int256 ethUsd) internal pure returns (int256) {
        int256 goldUsdPerGram = (goldUsdPerTroyOunce * 10_000_000) / 311_034_768;
        return (goldUsdPerGram * 10 ** 8) / ethUsd;
    }

    function test_mint_reverts_on_invalid_gold_price() public {
        // set gold feed to 0 so getGoldPriceInEth() <= 0
        goldAggregator.updateAnswer(int256(0));
        vm.expectRevert(IGoldToken.InvalidGoldPrice.selector);
        goldToken.mint{value: 1 ether}();
    }

    function test_mint_reverts_when_goldAmount_is_zero() public {
        // set an extremely large gold price so a tiny deposit yields 0 GLD
        // MockV3Aggregator uses 8 decimals, so use a very large value
        goldAggregator.updateAnswer(int256(10 ** 18));
        vm.expectRevert(IGoldToken.AmountMustBeGreaterThanZero.selector);
        goldToken.mint{value: 1}(); // 1 wei should produce 0 GLD at that price
    }

    function test_upgradeTo_succeeds_for_owner() public {
        GoldToken newImpl = new GoldToken();

        UUPSUpgradeable(address(goldToken)).upgradeToAndCall(address(newImpl), "");
    }

    function test_upgradeTo_reverts_for_non_owner() public {
        GoldToken newImpl = new GoldToken();
        address nonOwner = address(0x9);

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), nonOwner, OWNER_ROLE
            )
        );
        UUPSUpgradeable(address(goldToken)).upgradeToAndCall(address(newImpl), "");
    }

    fallback() external payable {}
    receive() external payable {}
}
