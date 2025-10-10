// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract AntiFragileSBT200 is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;

    uint256 public constant MIN_DEPOSIT = 0.03 ether;
    uint256 public constant LAZINESS_TAX = 0.01 ether;
    uint256 public constant LEAVE_FEE_PER_DAY = 0.0001 ether;
    uint256 public constant MAX_TOTAL_TAX = 0.1 ether;
    uint256 public constant LEARNING_DAYS = 148;
    uint256 public constant SILENCE_THRESHOLD = 3 days;
    uint16 public constant MAX_LEAVE_DAYS = 200;

    Counters.Counter private _tokenIdCounter;

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

    uint256 public feesAccumulated;

    event JourneyStarted(address indexed learner, uint256 tokenId, uint256 amount);
    event CommitRecorded(address indexed learner, bytes32 hash, uint256 effectiveDay);
    event LeaveStarted(address indexed learner, uint16 daysTaken, uint16 daysLeft, uint64 leaveEndTime);
    event LeaveEnded(address indexed learner);
    event TaxBurned(address indexed learner, uint256 amount, uint256 remainingDeposit);
    event JourneyCompleted(address indexed learner, uint256 refund, uint256 totalBurned, uint256 tokenId);
    event FeesWithdrawn(address indexed owner, uint256 amount);

    constructor() ERC721("AntiFragileLearner200", "LEARN200") {}

    function startJourney(bytes32 commitHash) external payable {
        if (msg.value < MIN_DEPOSIT) revert DepositTooLow();
        if (userTokenId[msg.sender] != 0) revert AlreadyActive();
        if (usedHash[commitHash]) revert HashUsed();

        usedHash[commitHash] = true;
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

        _cleanupUserState(learner);
        _burn(tokenId);

        (bool success, ) = payable(learner).call{value: refund}("");
        if (!success) revert TransferFail();

        emit JourneyCompleted(learner, refund, st.totalBurned, tokenId);
    }

    function topUpDeposit() external payable {
        if (userTokenId[msg.sender] == 0) revert NotActive();
        unchecked {
            userStates[msg.sender].depositBalance += uint128(msg.value);
        }
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = feesAccumulated;
        if (amount == 0) revert NoFees();
        feesAccumulated = 0;
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFail();
        emit FeesWithdrawn(owner(), amount);
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

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "NO_EXIST");
        address owner = ownerOf(tokenId);
        UserState memory st = userStates[owner];
        uint256 eff = _effectiveDays(st);
        
        string memory status = "Active";
        if (st.leaveEndTime > block.timestamp) {
            status = "On Leave";
        }
        
        string memory svg = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" viewBox="0 0 400 300">',
            '<rect width="400" height="300" fill="#1a1a1a"/>',
            '<text x="200" y="60" text-anchor="middle" fill="white" font-family="Arial" font-size="24">Anti-Fragile Learner</text>',
            '<text x="200" y="90" text-anchor="middle" fill="#FFD700" font-family="Arial" font-size="16">Status: ',
            status,
            '</text>',
            '<text x="200" y="120" text-anchor="middle" fill="#4CAF50" font-family="Arial" font-size="18">Effective Days: ',
            eff.toString(),
            '/',
            LEARNING_DAYS.toString(),
            '</text>',
            '<text x="200" y="150" text-anchor="middle" fill="#FF9800" font-family="Arial" font-size="16">Leave Days Used: ',
            uint256(st.totalLeaveDays).toString(),
            '/',
            MAX_LEAVE_DAYS.toString(),
            '</text>',
            '<text x="200" y="180" text-anchor="middle" fill="#2196F3" font-family="Arial" font-size="16">Deposit: ',
            _weiToEther(st.depositBalance),
            ' ETH</text>',
            '</svg>'
        ));

        string memory json = string(abi.encodePacked(
            '{"name":"Anti-Fragile Learner #',
            tokenId.toString(),
            '","description":"148-day learning commitment SBT with flexible leave system",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[',
            '{"trait_type":"Status","value":"',status,'"},',
            '{"trait_type":"Effective Days","value":"',eff.toString(),'"},',
            '{"trait_type":"Target Days","value":"',LEARNING_DAYS.toString(),'"},',
            '{"trait_type":"Leave Days Used","value":"',uint256(st.totalLeaveDays).toString(),'"},',
            '{"trait_type":"Max Leave Days","value":"',MAX_LEAVE_DAYS.toString(),'"},',
            '{"trait_type":"Total Burned","value":"',st.totalBurned.toString(),'"},',
            '{"trait_type":"Deposit Balance","value":"',_weiToEther(st.depositBalance),' ETH"}',
            ']}'
        ));

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
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

    function _weiToEther(uint256 weiValue) internal pure returns (string memory) {
        uint256 etherValue = weiValue / 1e18;
        uint256 fractional = (weiValue % 1e18) / 1e14;
        return string(abi.encodePacked(etherValue.toString(), ".", _padFractional(fractional)));
    }

    function _padFractional(uint256 fractional) internal pure returns (string memory) {
        if (fractional == 0) return "0000";
        string memory str = fractional.toString();
        uint256 len = bytes(str).length;
        if (len == 1) return string(abi.encodePacked("000", str));
        if (len == 2) return string(abi.encodePacked("00", str));
        if (len == 3) return string(abi.encodePacked("0", str));
        return str;
    }

    function _cleanupUserState(address learner) internal {
        delete userTokenId[learner];
        delete userStates[learner];
    }

    function _beforeTokenTransfer(address from, address to, uint256, uint256) internal pure override {
        if (from != address(0) && to != address(0)) revert NonTransferable();
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
}
