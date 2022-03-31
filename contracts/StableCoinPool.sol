//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./EIP712Alien.sol";
import "./LimitOrderProtocol.sol";

contract StableCoinPool is Ownable,EIP712Alien, ERC20, ReentrancyGuard {

    // ERROR-CODE
    // 1). AMT_ZERO: Amount is Zero
    // 2). INS_AMT: Insufficient amount

    IERC20 public underlyingToken;
    uint256 public totalAmount;
    address private immutable _limitOrderProtocol;
    address private immutable _oneInchExchange;
    uint256 makingAssetAmount = 1e18;
    uint256 takingAssetAmount = 99e19;


    event Deposit(address to, uint256 depositAmount, uint256 mintedShare);
    event Withdraw(address to, uint256 withdrawAmount, uint256 burnedShare);
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        bytes makerAssetData; // (transferFrom.selector, signer, ______, makerAmount, ...)
        bytes takerAssetData; // (transferFrom.selector, sender, signer, takerAmount, ...)
        bytes getMakerAmount; // this.staticcall(abi.encodePacked(bytes, swapTakerAmount)) => (swapMakerAmount)
        bytes getTakerAmount; // this.staticcall(abi.encodePacked(bytes, swapMakerAmount)) => (swapTakerAmount)
        bytes predicate;      // this.staticcall(bytes) => (bool)
        bytes permit;         // On first fill: permit.1.call(abi.encodePacked(permit.selector, permit.2))
        bytes interaction;
    }

    constructor(address limitOrderProtocol, address oneInchExchange)
    // constructor(address limitOrderProtocol, address oneInchExchange, ILendingPoolAddressesProvider addressProvider)
    EIP712Alien(limitOrderProtocol, "1inch Limit Order Protocol", "1")
    {
        _limitOrderProtocol = limitOrderProtocol;
        _oneInchExchange = oneInchExchange;
    }
    
    function deposit(uint256 _amount) external nonReentrant returns(uint256 share) {
        require(_amount > 0, "AMT_ZERO");
        
        underlyingToken.transferFrom(msg.sender, address(this), _amount);

        share = pricePerShare(_amount);
        // _mint(msg.sender, share);

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

        /// @notice callback from limit order protocol, executes on order fill
    function notifyFillOrder(
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        bytes memory interactiveData // abi.encode(orderHash)
    ) external {
        require(msg.sender == _limitOrderProtocol, "only LOP can exec callback");
        makerAsset;
        takingAmount;
        bytes32 orderHash;
        assembly {  // solhint-disable-line no-inline-assembly
            orderHash := mload(add(interactiveData, 32))
        }
        underlyingToken = takerAsset;
        totalAmount = IERC20(takerAsset).balanceOf(address(this));
    }

    function callFillOrder(Order memory order, bytes calldata signature,uint256 makingAmount, uint256 thresholdAmount) external {
        require(makingAmount > 1000e18, "INS_AMT");
        for (uint256 i=0; i<2; i++) {
            filloreder(order, signature, makingAmount, thresholdAmount);
        }
    }


    function filloreder(Order memory order, bytes calldata signature,uint256 makingAmount, uint256 thresholdAmount) external returns(uint256, uint256) {
        bytes32 orderHash = _hash(order);
        uint256 takingAmount = makingAmount/takingAssetAmount; // currently it's 0.99

        uint256 remainingMakerAmount;
        { // Stack too deep
            bool orderExists;
            (orderExists, remainingMakerAmount) = _remaining[orderHash].trySub(1);
            if (!orderExists) {
                // First fill: validate order and permit maker asset
                _validate(order.makerAssetData, order.takerAssetData, signature, orderHash);
                remainingMakerAmount = order.makerAssetData.decodeUint256(_AMOUNT_INDEX);
                if (order.permit.length > 0) {
                    (address token, bytes memory permit) = abi.decode(order.permit, (address, bytes));
                    token.uncheckedFunctionCall(abi.encodePacked(IERC20Permit.permit.selector, permit), "LOP: permit failed");
                    require(_remaining[orderHash] == 0, "LOP: reentrancy detected");
                }
            }
        }

        // Check if order is valid
        if (order.predicate.length > 0) {
            require(checkPredicate(order), "LOP: predicate returned false");
        }

        // Compute maker and taker assets amount
        if ((takingAmount == 0) == (makingAmount == 0)) {
            revert("LOP: only one amount should be 0");
        }
        else if (takingAmount == 0) {
            takingAmount = _callGetTakerAmount(order, makingAmount);
            require(takingAmount <= thresholdAmount, "LOP: taking amount too high");
        }
        else {
            makingAmount = _callGetMakerAmount(order, takingAmount);
            require(makingAmount >= thresholdAmount, "LOP: making amount too low");
        }

        require(makingAmount > 0 && takingAmount > 0, "LOP: can't swap 0 amount");

        // Update remaining amount in storage
        remainingMakerAmount = remainingMakerAmount.sub(makingAmount, "LOP: taking > remaining");
        _remaining[orderHash] = remainingMakerAmount + 1;
        emit OrderFilled(msg.sender, orderHash, remainingMakerAmount);

        // Taker => Maker
        _callTakerAssetTransferFrom(order.takerAsset, order.takerAssetData, msg.sender, takingAmount);

        // Maker can handle funds interactively
        if (order.interaction.length > 0) {
            InteractiveMaker(order.makerAssetData.decodeAddress(_FROM_INDEX))
                .notifyFillOrder(order.makerAsset, order.takerAsset, makingAmount, takingAmount, order.interaction);
        }

        // Maker => Taker
        _callMakerAssetTransferFrom(order.makerAsset, order.makerAssetData, msg.sender, makingAmount);

        return (makingAmount, takingAmount);

    }
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns(bytes4) {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        bytes memory makerAssetData;
        bytes memory takerAssetData;
        bytes memory getMakerAmount;
        bytes memory getTakerAmount;
        bytes memory predicate;
        bytes memory permit;
        bytes memory interaction;

        assembly {  // solhint-disable-line no-inline-assembly
            salt := mload(add(signature, 0x40))
            makerAsset := mload(add(signature, 0x60))
            takerAsset := mload(add(signature, 0x80))
            makerAssetData := add(add(signature, 0x40), mload(add(signature, 0xA0)))
            takerAssetData := add(add(signature, 0x40), mload(add(signature, 0xC0)))
            getMakerAmount := add(add(signature, 0x40), mload(add(signature, 0xE0)))
            getTakerAmount := add(add(signature, 0x40), mload(add(signature, 0x100)))
            predicate := add(add(signature, 0x40), mload(add(signature, 0x120)))
            permit := add(add(signature, 0x40), mload(add(signature, 0x140)))
            interaction := add(add(signature, 0x40), mload(add(signature, 0x160)))
        }
        bytes32 orderHash;
        assembly {  // solhint-disable-line no-inline-assembly
            orderHash := mload(add(interaction, 32))
        }

        require( // validate maker amount, address, asset address
            makerAssetData.decodeAddress(_FROM_INDEX) == address(this) &&
            _hash(salt, makerAsset, takerAsset, makerAssetData, takerAssetData, getMakerAmount, getTakerAmount, predicate, permit, interaction) == hash,
            "bad order"
        );


        return this.isValidSignature.selector;
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

    /// @notice validate signature from Limit Order Protocol, checks also asset and amount consistency
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns(bytes4) {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        bytes memory makerAssetData;
        bytes memory takerAssetData;
        bytes memory getMakerAmount;
        bytes memory getTakerAmount;
        bytes memory predicate;
        bytes memory permit;
        bytes memory interaction;

        assembly {  // solhint-disable-line no-inline-assembly
            salt := mload(add(signature, 0x40))
            makerAsset := mload(add(signature, 0x60))
            takerAsset := mload(add(signature, 0x80))
            makerAssetData := add(add(signature, 0x40), mload(add(signature, 0xA0)))
            takerAssetData := add(add(signature, 0x40), mload(add(signature, 0xC0)))
            getMakerAmount := add(add(signature, 0x40), mload(add(signature, 0xE0)))
            getTakerAmount := add(add(signature, 0x40), mload(add(signature, 0x100)))
            predicate := add(add(signature, 0x40), mload(add(signature, 0x120)))
            permit := add(add(signature, 0x40), mload(add(signature, 0x140)))
            interaction := add(add(signature, 0x40), mload(add(signature, 0x160)))
        }
        bytes32 orderHash;
        assembly {  // solhint-disable-line no-inline-assembly
            orderHash := mload(add(interaction, 32))
        }

        require( // validate maker amount, address, asset address
            makerAssetData.decodeAddress(_FROM_INDEX) == address(this) &&
            _hash(salt, makerAsset, takerAsset, makerAssetData, takerAssetData, getMakerAmount, getTakerAmount, predicate, permit, interaction) == hash,
            "bad order"
        );


        return this.isValidSignature.selector;
    }

    function _hash(
        uint256 salt,
        address makerAsset,
        address takerAsset,
        bytes memory makerAssetData,
        bytes memory takerAssetData,
        bytes memory getMakerAmount,
        bytes memory getTakerAmount,
        bytes memory predicate,
        bytes memory permit,
        bytes memory interaction
    ) internal view returns(bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    LIMIT_ORDER_TYPEHASH,
                    salt,
                    makerAsset,
                    takerAsset,
                    keccak256(makerAssetData),
                    keccak256(takerAssetData),
                    keccak256(getMakerAmount),
                    keccak256(getTakerAmount),
                    keccak256(predicate),
                    keccak256(permit),
                    keccak256(interaction)
                )
            )
        );
    }

}
