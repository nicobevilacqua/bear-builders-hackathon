// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ISenseiStake} from "./ISenseiStake.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title Vault instance
 * @author StakeTogether
 * @dev Contract created every time `VAULT_AMOUNT` is reached by `VaultManager`
 */
contract Vault is ERC4626, Initializable, IERC721Receiver {
    /**
     * @dev reference to SenseiNode contract
     */
    ISenseiStake public immutable stake;

    /**
     * @dev Max amount of weth to be transfered to the vault
     */
    uint256 public immutable VAULT_AMOUNT;

    uint256 public tokenId;
    uint256 public totalEarns;

    CurrentState public state;
    enum CurrentState {
        FUNDING,
        WORKING,
        FINISHED
    }

    constructor(
        address _stake,
        uint256 _VAULT_AMOUNT,
        address _weth
    ) ERC4626(ERC20(_weth), "StakeTogetherToken", "STT") {
        require(_VAULT_AMOUNT > 0, "Invalid VAULT_AMOUNT");

        VAULT_AMOUNT = _VAULT_AMOUNT;

        stake = ISenseiStake(_stake);
    }

    receive() external payable {}

    function initialize() external initializer {
        // TODO ver que datos extras necesitamos setear
    }

    function maxDeposit() public view returns (uint256) {
        return VAULT_AMOUNT;
    }

    function maxMint(address) public view override returns (uint256) {
        return VAULT_AMOUNT;
    }

    function beforeWithdraw(uint256, uint256) internal view override {
        require(state != CurrentState.WORKING, "node working, funds lock");
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function afterDeposit(uint256, uint256) internal override {
        require(state == CurrentState.FUNDING, "cant deposit");

        // Lock contract if VAULT_AMOUNT is reached
        if (totalAssets() == VAULT_AMOUNT) {
            state = CurrentState.WORKING;
            WETH(payable(address(asset))).withdraw(VAULT_AMOUNT);
            tokenId = stake.buyNode{value: VAULT_AMOUNT}();
        }
    }

    function redeemETH(uint256 assets) external {
        WETH _weth = WETH(payable(address(asset)));
        uint256 _earn = previewRedeem(assets);
        redeem(assets, address(this), msg.sender);
        _weth.withdraw(_earn);
        (bool sent, ) = address(msg.sender).call{value: _earn}("");
        require(sent, "send failed");
    }

    function beforeWithdraw(
        address,
        address,
        address,
        uint256,
        uint256
    ) internal view {
        require(state == CurrentState.FUNDING || state == CurrentState.FINISHED, "vault locked");
    }

    function exitStake() external {
        state = CurrentState.FINISHED;
        stake.exitStake(tokenId);
        totalEarns = address(this).balance;
        (bool sent, ) = address(asset).call{value: address(this).balance}("");
        require(sent, "send failed");
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function exitDate() external view returns (uint256) {
        return stake.exitDate(tokenId);
    }

    function canExit() external view returns (bool) {
        return stake.exitDate(tokenId) < block.timestamp;
    }
}
