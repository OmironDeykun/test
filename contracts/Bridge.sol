// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "openzeppelin-solidity/contracts/access/AccessControl.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";

import "contracts/Pool.sol";

contract Bridge is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SWAP_OPERATOR_ROLE =
        keccak256("SWAP_OPERATOR_ROLE");

    enum State {Empty, Active, Redeemed, Refunded}

    struct Swap {
        uint256 initTimestamp;
        string hashedSecret;
        bytes secret;
        address initiator;
        uint256 amount;
        string symbol_from;
        string symbol_to;
        State state;
    }

    // symbol => ERC20 address
    mapping(string => address) public CoinAddressBySymbol;
    // ERC20 address => symbol
    mapping(address => string) public CoinSymbolByAddress;

    // ERC20 addresses
    address[] public CoinAddresses;

    // hashedSecret => swap data
    mapping(string => Swap) public Swaps;

    address pool;

    /**
     * @dev Emitted when Swap created.
     */
    event SwapInitialized(
        address indexed Initiator,
        address Recipient,
        uint256 Amount,
        string Symbol,
        string HashedSecret,
        uint256 InitTimestamp
    );

    /**
     * @dev Emitted when Swap redeemed.
     */
    event SwapRedeemed(string indexed HashedSecret, uint256 RedeemTimestamp);

    /**
     * @dev Emitted when new coin added.
     */
    event NewCoinAdded(address coin, string symbol);

    constructor() public {
        // Grant the contract deployer the default admin role: it will be able
        // to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(SWAP_OPERATOR_ROLE, msg.sender);
        // Sets `DEFAULT_ADMIN_ROLE` as ``ADMIN_ROLE``'s admin role.
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        // Sets `ADMIN_ROLE` as ``SWAP_OPERATOR_ROLE``'s admin role.
        _setRoleAdmin(SWAP_OPERATOR_ROLE, ADMIN_ROLE);
    }

    function setPool(address _pool) public {
        require(
            hasRole(ADMIN_ROLE, msg.sender),
            "Bridge: Caller is not a admin"
        );
        pool = _pool;
    }

    /**
     * @dev Creates new swap.
     *
     * Emits a {SwapInitialized} event.
     *
     * Requirements
     *
     * - `Symbol` must be already registered.
     */
    function swap(
        uint256 _transaction_number,
        uint256 _amount,
        string memory _transaction_symbol,
        string memory _transaction_symbol_from,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public payable {
        string memory message =
            string(
                abi.encodePacked(
                    uint2str(_transaction_number),
                    uint2str(_amount),
                    _transaction_symbol
                )
            );

        require(
            Swaps[message].state == State.Empty,
            "Bridge: swap is not empty state or dublicate secret and hash"
        );

        require(
            CoinAddressBySymbol[_transaction_symbol] != address(0),
            "Bridge: coin is not registered"
        );

        address addr = recovery(message, _v, _r, _s);

        require(addr == msg.sender, "Bridge: sender is not recipient");

        IERC20(CoinAddressBySymbol[_transaction_symbol_from]).safeTransferFrom(
            msg.sender,
            pool,
            _amount
        );

        Swaps[message].initTimestamp = block.timestamp;
        Swaps[message].hashedSecret = message;
        Swaps[message].initiator = msg.sender;
        Swaps[message].amount = _amount;
        Swaps[message].symbol_from = _transaction_symbol_from;
        Swaps[message].symbol_to = _transaction_symbol;
        Swaps[message].state = State.Active;

        emit SwapInitialized(
            msg.sender,
            msg.sender,
            _amount,
            _transaction_symbol,
            message,
            Swaps[message].initTimestamp
        );
    }

    /**
     * @dev Redeem initialized swap.
     *
     * Emits a {SwapRedeemed} event.
     *
     */
    function redeem(
        uint256 _transaction_number,
        uint256 _amount,
        string memory _transaction_symbol,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public nonReentrant {
        string memory message =
            string(
                abi.encodePacked(
                    uint2str(_transaction_number),
                    uint2str(_amount),
                    _transaction_symbol
                )
            );

        address addr = recovery(message, _v, _r, _s);

        require(addr == msg.sender, "Bridge: sender is not recipient");

        require(
            Swaps[message].state == State.Empty,
            "Bridge: swap is not empty state or dublicate secret and hash"
        );

        require(
            hasRole(SWAP_OPERATOR_ROLE, addr),
            "Bridge: signer is not swap operator"
        );

        require(
            IERC20(CoinAddressBySymbol[_transaction_symbol]).balanceOf(
                msg.sender
            ) >= _amount,
            "Bridge: not enough balance in pool"
        );

        Swaps[message].state = State.Redeemed;

        Pool(pool).transfer(
            CoinAddressBySymbol[_transaction_symbol],
            msg.sender,
            _amount
        );

        emit SwapRedeemed(message, block.timestamp);
    }

    /**
     * @dev Register new coin symbol and contract address.
     *
     * Emits a {NewCoinAdded} event.
     *
     */
    function addCoin(address _coin, string memory _symbol) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender),
            "Bridge: Caller is not a admin"
        );

        CoinAddressBySymbol[_symbol] = _coin;
        CoinSymbolByAddress[_coin] = _symbol;
        CoinAddresses.push(_coin);

        emit NewCoinAdded(_coin, _symbol);
    }

    /**
     * @dev Returns `ERC20` contract address by symbol.
     *
     */
    function getCoinAddressBySymbol(string memory _symbol)
        external
        view
        returns (address coin)
    {
        return CoinAddressBySymbol[_symbol];
    }

    /**
     * @dev Returns swap state.
     *
     */
    function getSwapState(string memory _HashedSecret)
        external
        view
        returns (State state)
    {
        return Swaps[_HashedSecret].state;
    }



    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function recovery(
        string memory message,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public view returns (address) {
        // The message header; we will fill in the length next
        string memory header = "\x19Ethereum Signed Message:\n000000";

        uint256 lengthOffset;
        uint256 length;

        assembly {
            // The first word of a string is its length
            length := mload(message)

            // The beginning of the base-10 message length in the prefix
            lengthOffset := add(header, 57)
        }

        // Maximum length we support
        require(length <= 999999);

        // The length of the message's length in base-10
        uint256 lengthLength = 0;

        // The divisor to get the next left-most message length digit
        uint256 divisor = 100000;

        // Move one digit of the message length to the right at a time
        while (divisor != 0) {
            // The place value at the divisor
            uint256 digit = length / divisor;
            if (digit == 0) {
                // Skip leading zeros
                if (lengthLength == 0) {
                    divisor /= 10;
                    continue;
                }
            }

            // Found a non-zero digit or non-leading zero digit
            lengthLength++;

            // Remove this digit from the message length's current value
            length -= digit * divisor;

            // Shift our base-10 divisor over
            divisor /= 10;

            // Convert the digit to its ASCII representation (man ascii)
            digit += 0x30;

            // Move to the next character and write the digit
            lengthOffset++;
            assembly {
                mstore8(lengthOffset, digit)
            }
        }
        // The null string requires exactly 1 zero (unskip 1 leading 0)
        if (lengthLength == 0) {
            lengthLength = 1 + 0x19 + 1;
        } else {
            lengthLength += 1 + 0x19;
        }
        // Truncate the tailing zeros from the header
        assembly {
            mstore(header, lengthLength)
        }
        // Perform the elliptic curve recover operation
        bytes32 check = keccak256(abi.encodePacked(header, message));
        // bytes32 check = keccak256(header, message);
        // bytes32 check = abi.encode(header, message);

        return ecrecover(check, v, r, s);
    }
}
