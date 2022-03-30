//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract StableCoinPool is OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable {

    // ERROR-CODE
    // 1). AMT_ZERO: Amount is Zero
    // 2). INS_AMT: Insufficient amount

    IERC20Upgradeable public underlyingToken;
    uint256 public totalAmount;

    event Deposit(address to, uint256 depositAmount, uint256 mintedShare);
    event Withdraw(address to, uint256 withdrawAmount, uint256 burnedShare);

    constructor(
        address _underlyingToken
    ) {
        __Ownable_init();
        __ERC20_init("BearingToken", "bear");
        underlyingToken = IERC20Upgradeable(_underlyingToken);
    }

    function deposit(uint256 _amount) external nonReentrant returns(uint256 share) {
        require(_amount > 0, "AMT_ZERO");
        
        underlyingToken.transferFrom(msg.sender, address(this), _amount);

        share = pricePerShare(_amount);
        _mint(msg.sender, share);

        totalAmount = totalAmount + _amount;
        emit Deposit(msg.sender, _amount, share);
    }

    function withdraw(uint256 _share) external nonReentrant returns(uint256 underlyingTokens) {
        require(_share > 0, "AMT_ZERO");
        require(_share <= balanceOf(msg.sender), "INS_AMT");
        
        underlyingTokens = sharePerPrice(_share);
        underlyingToken.transfer(msg.sender, underlyingTokens);

        totalAmount = totalAmount - underlyingTokens;
        _burn(msg.sender, _share);
        
        emit Withdraw(msg.sender, underlyingTokens, _share);
    }

    function pricePerShare(uint256 _amount) public view returns(uint256 share) {
        return _amount * totalSupply() / totalAmount ;
    }

    function sharePerPrice(uint256 _share) public view returns(uint256 underlyingAmount) {
        return _share * totalAmount / totalSupply();
    }

    function underlying() public view returns(address) {
        return address(underlyingToken);
    }

}
