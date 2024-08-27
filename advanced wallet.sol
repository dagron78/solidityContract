// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EnhancedWallet is ReentrancyGuard {
    // Custom Errors
    error OnlyOwner();
    error Paused();
    error InsufficientBalance();
    error DailyLimit();
    error NotWhitelisted();
    error InvalidRecipient();
    error InsufficientTokens();
    error TransferFailed();
    error ArrayMismatch();
    error InvalidTime();
    error NoWithdrawal();
    error NoChange();
    error InvalidOwner();
    error InsufficientContractBalance();
    address public owner;
    mapping(address => uint256) public balances;
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public dailyLimits;
    mapping(address => uint256) public lastWithdrawalDay;
    
    uint256 public constant MAX_DAILY_LIMIT = 10 ether;
    uint256 public constant WEI_PER_ETHER = 1e18;
    uint256 public constant WITHDRAWAL_DELAY = 1 days;
    uint256 public constant MAX_DELAY_VARIANCE = 15 minutes;
    bool public paused;
    
    struct PendingWithdrawal {
        uint256 amount;
        uint256 releaseTime;
    }
    mapping(address => PendingWithdrawal) public pendingWithdrawals;

    event Deposit(address indexed sender, uint256 amountEther);
    event Withdrawal(address indexed recipient, uint256 amountEther);
    event Transfer(address indexed from, address indexed to, uint256 amountEther);
    event WithdrawalRequested(address indexed recipient, uint256 amountEther, uint256 releaseTime);
    event WhitelistUpdated(address indexed account, bool status);

    // Constructor with explicit visibility
    constructor() {
        owner = msg.sender;
    }

    // Explicit visibility modifiers for all functions
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    receive() external payable {
        deposit();
    }

    fallback() external payable {
        deposit();
    }

    function deposit() public payable notPaused {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, toEther(msg.value));
    }

    function requestWithdrawal(uint256 amountEther) public notPaused nonReentrant {
        uint256 amountWei = toWei(amountEther);
        require(balances[msg.sender] >= amountWei, "Insufficient balance");
        
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastWithdrawalDay[msg.sender]) {
            lastWithdrawalDay[msg.sender] = currentDay;
            dailyLimits[msg.sender] = 0;
        }
        
        require(dailyLimits[msg.sender] + amountWei <= MAX_DAILY_LIMIT, "Daily limit exceeded");
        
        balances[msg.sender] -= amountWei;
        dailyLimits[msg.sender] += amountWei;

        uint256 releaseTime = block.timestamp + WITHDRAWAL_DELAY;
        pendingWithdrawals[msg.sender] = PendingWithdrawal(amountWei, releaseTime);
        
        emit WithdrawalRequested(msg.sender, amountEther, releaseTime);
    }

    function executeWithdrawal() public notPaused nonReentrant {
        require(pendingWithdrawals[msg.sender].amount > 0, "No pending withdrawal");
        uint256 releaseTime = pendingWithdrawals[msg.sender].releaseTime;
        uint256 maxReleaseTime = releaseTime + MAX_DELAY_VARIANCE;
        require(block.timestamp >= releaseTime && block.timestamp <= maxReleaseTime, "Invalid time window");

        uint256 amount = pendingWithdrawals[msg.sender].amount;
        delete pendingWithdrawals[msg.sender];

        _transfer(address(this), msg.sender, amount);
    }

    function cancelWithdrawal() public notPaused {
        require(pendingWithdrawals[msg.sender].amount > 0, "No pending withdrawal");
        
        uint256 amount = pendingWithdrawals[msg.sender].amount;
        delete pendingWithdrawals[msg.sender];
        balances[msg.sender] += amount;
        dailyLimits[msg.sender] -= amount;
    }

    function getBalance() public view returns (uint256) {
        return toEther(balances[msg.sender]);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    function sendEther(address recipient, uint256 amountEther) public notPaused nonReentrant {
        uint256 amountWei = toWei(amountEther);
        require(balances[msg.sender] >= amountWei, "Insufficient balance");
        require(recipient != address(0), "Invalid recipient address");
        require(whitelist[recipient] || amountWei <= MAX_DAILY_LIMIT, "Recipient not whitelisted for large transfers");
        
        _transfer(msg.sender, recipient, amountWei);
    }

    function updateWhitelist(address account, bool status) public onlyOwner {
        require(whitelist[account] != status, "Whitelist status already set");
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    function withdrawERC20(IERC20 token, uint256 amount) public notPaused nonReentrant {
        require(token.balanceOf(address(this)) >= amount, "Insufficient token balance");
        require(token.transfer(msg.sender, amount), "Token transfer failed");
    }

    function pause() public onlyOwner {
        paused = true;
    }

    function unpause() public onlyOwner {
        paused = false;
    }

    function batchTransfer(address[] memory recipients, uint256[] memory amounts) public notPaused nonReentrant {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        
        uint256 totalAmount = 0;
        for (uint i = 0; i < recipients.length; i++) {
            totalAmount += amounts[i];
            require(balances[msg.sender] >= totalAmount, "Insufficient balance");
            
            address recipient = recipients[i];
            uint256 amount = amounts[i];
            require(recipient != address(0), "Invalid recipient address");

            _transfer(msg.sender, recipient, amount);
        }
    }

    function _transfer(address from, address to, uint256 amountWei) internal {
        balances[from] -= amountWei;

        emit Transfer(from, to, toEther(amountWei));

        require(address(this).balance >= amountWei, "Insufficient contract balance");
        payable(to).transfer(amountWei);
    }

    function toWei(uint256 etherAmount) internal pure returns (uint256) {
        return etherAmount * WEI_PER_ETHER;
    }

    function toEther(uint256 weiAmount) internal pure returns (uint256) {
        return weiAmount / WEI_PER_ETHER;
    }
}
