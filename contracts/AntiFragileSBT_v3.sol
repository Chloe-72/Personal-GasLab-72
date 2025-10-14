// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ITokenURIProvider.sol";

contract AntiFragileSBT200 is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    uint256 public constant MIN_DEPOSIT = 0.03 ether;
    uint256 public constant LAZINESS_TAX = 0.01 ether;
    uint256 public constant LEAVE_FEE_PER_DAY = 0.0001 ether;
    uint256 public constant MAX_TOTAL_TAX = 0.1 ether;
    uint256 public constant LEARNING_DAYS = 148;
    uint16 public constant MAX_LEAVE_DAYS = 1000;
    uint256 public constant SILENCE_THRESHOLD = 3 days;

    Counters.Counter private _tokenIdCounter;
    uint256 public feesAccumulated;

    struct UserState {
        uint128 depositBalance;
        uint64 lastActiveTime;
        uint64 startTime;
        uint32 totalBurned;
        uint16 totalLeaveDays;
        uint64 leaveEndTime;
    }

    mapping(address => uint256) public userTokenId;
    mapping(address => UserState) public userStates;
    mapping(bytes32 => bool) public usedHash;

    event JourneyStarted(address indexed learner, uint256 tokenId, uint256 amount);
    event CommitRecorded(address indexed learner, bytes32 hash, uint256 effectiveDay);
    event LeaveStarted(address indexed learner, uint16 daysTaken, uint16 daysLeft, uint64 leaveEndTime);
    event LeaveEnded(address indexed learner);
    event TaxBurned(address indexed learner, uint256 amount, uint256 remainingDeposit);
    event JourneyCompleted(address indexed learner, uint256 refund, uint256 totalBurned, uint256 tokenId);
    event FeesWithdrawn(address indexed owner, uint256 amount);

    ITokenURIProvider public immutable TOKEN_URI_PROVIDER;

    constructor(address _owner, address _provider) ERC721("AntiFragileLearner200", "LEARN200") Ownable(_owner) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_provider == address(0)) revert ZeroAddress();
        TOKEN_URI_PROVIDER = ITokenURIProvider(_provider);
    }

    function metadataIntegrityCheck(address learner) external view returns (bool) {
        if (userTokenId[learner] == 0) return false;
        UserState memory st = userStates[learner];
        uint256 onChainEff = _effectiveDays(st);
        try TOKEN_URI_PROVIDER.rawData(learner) returns (uint256 providerEff) {
            return onChainEff == providerEff;
        } catch {
            return false;
        }
    }

    function startJourney(bytes32 commitHash) external payable {
        if (msg.value < MIN_DEPOSIT) revert DepositTooLow();
        if (userTokenId[msg.sender] != 0) revert AlreadyActive();
        if (usedHash[commitHash]) revert HashUsed();

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _mint(msg.sender, tokenId);

        userTokenId[msg.sender] = tokenId;

        uint64 start = uint64(block.timestamp);
        userStates[msg.sender] = UserState({
            depositBalance: uint128(msg.value),
            lastActiveTime: start,
            startTime: start,
            totalBurned: 0,
            totalLeaveDays: 0,
            leaveEndTime: 0
        });
        usedHash[commitHash] = true;

        emit JourneyStarted(msg.sender, tokenId, msg.value);
        emit CommitRecorded(msg.sender, commitHash, 1);
    }

    function recordCommit(bytes32 commitHash) external {
        uint256 tokenId = userTokenId[msg.sender];
        if (tokenId == 0) revert NotActive();
        if (usedHash[commitHash]) revert HashUsed();
        
        UserState storage st = userStates[msg.sender];
        
        if (st.leaveEndTime > block.timestamp) revert InLeavePeriod();
        if (st.leaveEndTime != 0) {
            st.leaveEndTime = 0;
            emit LeaveEnded(msg.sender);
        }

        usedHash[commitHash] = true;

        uint256 nowDay = _dayNumberClock(msg.sender, block.timestamp);
        uint256 lastDay = _dayNumberClock(msg.sender, st.lastActiveTime);

        if (nowDay != lastDay && nowDay != lastDay + 1) revert GapNotClosed();

        st.lastActiveTime = uint64(block.timestamp);

        uint256 effectiveDay = _calculateEffectiveDay(st);
        emit CommitRecorded(msg.sender, commitHash, effectiveDay);
    }

    function takeLeave(uint16 days_) external payable nonReentrant {
        if (days_ == 0 || days_ > MAX_LEAVE_DAYS) revert InvalidDays();
        UserState storage st = userStates[msg.sender];
        if (userTokenId[msg.sender] == 0) revert NotActive();
        if (st.totalLeaveDays + days_ > MAX_LEAVE_DAYS) revert LeaveCap();
        if (st.leaveEndTime > block.timestamp) revert AlreadyOnLeave();

        uint256 fee = uint256(days_) * LEAVE_FEE_PER_DAY;
        if (msg.value != fee) revert IncorrectFee();

        uint64 leaveEnd = uint64(block.timestamp + days_ * 1 days);
        st.leaveEndTime = leaveEnd;
        st.totalLeaveDays += days_;
        st.lastActiveTime = uint64(block.timestamp);

        feesAccumulated += fee;
        emit LeaveStarted(msg.sender, days_, MAX_LEAVE_DAYS - st.totalLeaveDays, leaveEnd);
    }

    function triggerTax() external nonReentrant {
        if (userTokenId[msg.sender] == 0) revert NotActive();
        if (_isRestDay(block.timestamp)) return;

        UserState storage st = userStates[msg.sender];
        if (st.leaveEndTime > block.timestamp) return;

        uint256 silence = block.timestamp - st.lastActiveTime;
        if (silence < SILENCE_THRESHOLD) revert StillSafe();

        uint256 burn = LAZINESS_TAX;
        if (st.totalBurned + burn > MAX_TOTAL_TAX) revert TaxCapReached();
        if (st.depositBalance < burn) revert InsufficientDeposit();

        unchecked {
            st.totalBurned += uint32(burn);
            st.depositBalance -= uint128(burn);
        }

        (bool success, ) = payable(0x000000000000000000000000000000000000dEaD).call{value: burn}("");
        if (!success) revert TransferFail();

        st.lastActiveTime = uint64(block.timestamp);
        emit TaxBurned(msg.sender, burn, st.depositBalance);
    }

    function completeJourney() external nonReentrant {
        address learner = msg.sender;
        uint256 tokenId = userTokenId[learner];
        if (tokenId == 0) revert NotActive();

        UserState memory st = userStates[learner];
        uint256 effectiveDays = _effectiveDays(st);
        if (effectiveDays < LEARNING_DAYS) revert TooEarly();

        uint256 refund = st.depositBalance;
        if (refund == 0) revert NothingToRefund();

        require(ownerOf(tokenId) == learner, "Not owner");
        _burn(tokenId);
        _cleanupUserState(learner);

        (bool success, ) = payable(learner).call{value: refund}("");
        if (!success) revert TransferFail();

        emit JourneyCompleted(learner, refund, st.totalBurned, tokenId);
    }

    function topUpDeposit() external payable {
        if (userTokenId[msg.sender] == 0) revert NotActive();
        UserState storage st = userStates[msg.sender];
        uint256 newBal = uint256(st.depositBalance) + msg.value;
        if (newBal > type(uint128).max) revert Overflow();
        st.depositBalance = uint128(newBal);
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = feesAccumulated;
        if (amount == 0) revert NoFees();
        
        address feeOwner = owner();
        if (feeOwner == address(0)) revert ZeroAddress();
        
        feesAccumulated = 0;
        (bool success, ) = payable(feeOwner).call{value: amount}("");
        if (!success) revert TransferFail();
        emit FeesWithdrawn(feeOwner, amount);
    }

    function getTotalBurned() external view returns (uint256) {
        UserState memory st = userStates[msg.sender];
        return st.totalBurned;
    }

    function effectiveDays(address learner) external view returns (uint256) {
        if (userTokenId[learner] == 0) return 0;
        return _effectiveDays(userStates[learner]);
    }

    function getRemainingLeaveDays(address learner) external view returns (uint16) {
        if (userTokenId[learner] == 0) return 0;
        UserState memory st = userStates[learner];
        return MAX_LEAVE_DAYS - st.totalLeaveDays;
    }

    function isOnLeave(address learner) external view returns (bool) {
        if (userTokenId[learner] == 0) return false;
        UserState memory st = userStates[learner];
        return st.leaveEndTime > block.timestamp;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);
        address owner = ownerOf(tokenId);
        UserState memory st = userStates[owner];
        uint256 eff = _effectiveDays(st);
        
        try TOKEN_URI_PROVIDER.tokenURI(
            tokenId,
            owner,
            eff,
            st.totalLeaveDays,
            st.depositBalance,
            st.totalBurned
        ) returns (string memory uri) {
            return uri;
        } catch {
            return _fallbackTokenURI(tokenId, owner, st);
        }
    }

    function _calculateEffectiveDay(UserState memory st) internal view returns (uint256) {
        uint256 totalDays = (block.timestamp - st.startTime) / 1 days + 1;
        uint256 effective = totalDays > st.totalLeaveDays ? totalDays - st.totalLeaveDays : 1;
        return effective;
    }

    function _effectiveDays(UserState memory st) internal view returns (uint256) {
        return _calculateEffectiveDay(st);
    }

    function _dayNumberClock(address learner, uint256 ts) internal view returns (uint256) {
        UserState memory st = userStates[learner];
        if (st.startTime == 0) revert NotStarted();
        return ((ts - st.startTime) / 1 days) + 1;
    }

    function _isRestDay(uint256 ts) internal pure returns (bool) {
        return ((ts / 1 days + 3) % 7) >= 5;
    }

    function _fallbackTokenURI(uint256 tokenId, address owner, UserState memory st) internal pure returns (string memory) {
        string memory base = string(abi.encodePacked(
            '{"name":"Anti-Fragile Learner #',
            _toString(tokenId),
            '","description":"148-day learning commitment SBT"}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", _base64Encode(bytes(base))));
    }

    function _cleanupUserState(address learner) internal {
        delete userTokenId[learner];
        delete userStates[learner];
    }

    function _beforeTokenTransfer(address from, address to, uint256, uint256) internal pure override {
        if (from != address(0) && to != address(0)) revert NonTransferable();
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        string memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);

        assembly {
            mstore(result, encodedLen)
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)

            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }

            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }

        return result;
    }

    error DepositTooLow();
    error AlreadyActive();
    error HashUsed();
    error NotActive();
    error NotStarted();
    error InvalidDays();
    error LeaveCap();
    error IncorrectFee();
    error GapNotClosed();
    error InLeavePeriod();
    error AlreadyOnLeave();
    error NotOnLeave();
    error StillSafe();
    error TaxCapReached();
    error InsufficientDeposit();
    error TransferFail();
    error TooEarly();
    error NothingToRefund();
    error NoFees();
    error NonTransferable();
    error ZeroAddress();
    error Overflow();
}
