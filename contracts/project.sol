// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Compliment Coin
 * @dev ERC-20 token that rewards users for giving and receiving compliments
 * Features:
 * - Users earn tokens for giving compliments
 * - Recipients earn bonus tokens for receiving compliments
 * - Anti-spam mechanisms to prevent abuse
 * - Reputation system based on compliment quality
 * - Governance features for community management
 */
contract ComplimentCoin is ERC20, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    // Token configuration
    uint256 public constant MAX_SUPPLY = 1000000 * 10**18; // 1 million tokens
    uint256 public constant COMPLIMENT_REWARD = 10 * 10**18; // 10 tokens for giving compliment
    uint256 public constant RECIPIENT_BONUS = 5 * 10**18; // 5 tokens for receiving compliment
    uint256 public constant DAILY_LIMIT = 5; // Max compliments per user per day
    
    // Structs
    struct Compliment {
        uint256 id;
        address giver;
        address recipient;
        string message;
        uint256 timestamp;
        uint256 likes;
        bool isActive;
    }
    
    struct UserStats {
        uint256 complimentsGiven;
        uint256 complimentsReceived;
        uint256 reputation;
        uint256 lastComplimentDate;
        uint256 dailyComplimentCount;
        bool isModerator;
    }
    
    // State variables
    Counters.Counter private _complimentIds;
    mapping(uint256 => Compliment) public compliments;
    mapping(address => UserStats) public userStats;
    mapping(uint256 => mapping(address => bool)) public complimentLikes;
    mapping(address => bool) public blacklistedUsers;
    
    // Events
    event ComplimentGiven(
        uint256 indexed complimentId,
        address indexed giver,
        address indexed recipient,
        string message,
        uint256 timestamp
    );
    
    event ComplimentLiked(
        uint256 indexed complimentId,
        address indexed liker,
        uint256 totalLikes
    );
    
    event ReputationUpdated(
        address indexed user,
        uint256 newReputation
    );
    
    event UserBlacklisted(address indexed user);
    event UserWhitelisted(address indexed user);
    event ModeratorAdded(address indexed moderator);
    event ModeratorRemoved(address indexed moderator);
    
    // Modifiers
    modifier notBlacklisted(address user) {
        require(!blacklistedUsers[user], "User is blacklisted");
        _;
    }
    
    modifier validCompliment(address recipient, string memory message) {
        require(recipient != address(0), "Invalid recipient");
        require(recipient != msg.sender, "Cannot compliment yourself");
        require(bytes(message).length > 0 && bytes(message).length <= 280, "Invalid message length");
        _;
    }
    
    modifier dailyLimitNotExceeded() {
        UserStats storage stats = userStats[msg.sender];
        if (block.timestamp >= stats.lastComplimentDate + 1 days) {
            stats.dailyComplimentCount = 0;
            stats.lastComplimentDate = block.timestamp;
        }
        require(stats.dailyComplimentCount < DAILY_LIMIT, "Daily compliment limit exceeded");
        _;
    }
    
    constructor() ERC20("Compliment Coin", "COMP") Ownable(msg.sender) {
        // Mint initial supply to contract owner
        _mint(msg.sender, MAX_SUPPLY / 10); // 10% to owner for initial distribution
        userStats[msg.sender].isModerator = true;
    }
    
    /**
     * @dev Give a compliment to another user
     * @param recipient Address of the compliment recipient
     * @param message Compliment message
     */
    function giveCompliment(
        address recipient,
        string memory message
    ) 
        external 
        nonReentrant
        notBlacklisted(msg.sender)
        notBlacklisted(recipient)
        validCompliment(recipient, message)
        dailyLimitNotExceeded
    {
        _complimentIds.increment();
        uint256 complimentId = _complimentIds.current();
        
        // Create compliment record
        compliments[complimentId] = Compliment({
            id: complimentId,
            giver: msg.sender,
            recipient: recipient,
            message: message,
            timestamp: block.timestamp,
            likes: 0,
            isActive: true
        });
        
        // Update user statistics
        userStats[msg.sender].complimentsGiven++;
        userStats[msg.sender].dailyComplimentCount++;
        userStats[recipient].complimentsReceived++;
        
        // Update reputation
        _updateReputation(msg.sender, 10); // Reputation points for giving
        _updateReputation(recipient, 15); // More points for receiving
        
        // Mint rewards
        if (totalSupply() + COMPLIMENT_REWARD + RECIPIENT_BONUS <= MAX_SUPPLY) {
            _mint(msg.sender, COMPLIMENT_REWARD);
            _mint(recipient, RECIPIENT_BONUS);
        }
        
        emit ComplimentGiven(complimentId, msg.sender, recipient, message, block.timestamp);
    }
    
    /**
     * @dev Like a compliment
     * @param complimentId ID of the compliment to like
     */
    function likeCompliment(uint256 complimentId) external notBlacklisted(msg.sender) {
        require(compliments[complimentId].isActive, "Compliment does not exist or is inactive");
        require(!complimentLikes[complimentId][msg.sender], "Already liked this compliment");
        require(compliments[complimentId].giver != msg.sender, "Cannot like your own compliment");
        
        complimentLikes[complimentId][msg.sender] = true;
        compliments[complimentId].likes++;
        
        // Give bonus reputation to compliment giver
        address giver = compliments[complimentId].giver;
        _updateReputation(giver, 2);
        
        // Small reward for engagement
        if (totalSupply() + 1 * 10**18 <= MAX_SUPPLY) {
            _mint(msg.sender, 1 * 10**18); // 1 token for liking
        }
        
        emit ComplimentLiked(complimentId, msg.sender, compliments[complimentId].likes);
    }
    
    /**
     * @dev Get compliments given by a user
     * @param user Address of the user
     * @param offset Starting index
     * @param limit Number of compliments to return
     */
    function getComplimentsByGiver(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (Compliment[] memory) {
        require(limit <= 50, "Limit too high");
        
        uint256 totalCompliments = _complimentIds.current();
        uint256 count = 0;
        
        // Count matching compliments
        for (uint256 i = 1; i <= totalCompliments; i++) {
            if (compliments[i].giver == user && compliments[i].isActive) {
                count++;
            }
        }
        
        if (offset >= count || limit == 0) {
            return new Compliment ;
        }
        
        uint256 resultSize = (offset + limit > count) ? count - offset : limit;
        Compliment[] memory result = new Compliment[](resultSize);
        
        uint256 found = 0;
        uint256 resultIndex = 0;
        
        for (uint256 i = 1; i <= totalCompliments && resultIndex < resultSize; i++) {
            if (compliments[i].giver == user && compliments[i].isActive) {
                if (found >= offset) {
                    result[resultIndex] = compliments[i];
                    resultIndex++;
                }
                found++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev Get compliments received by a user
     * @param user Address of the user
     * @param offset Starting index
     * @param limit Number of compliments to return
     */
    function getComplimentsByRecipient(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (Compliment[] memory) {
        require(limit <= 50, "Limit too high");
        
        uint256 totalCompliments = _complimentIds.current();
        uint256 count = 0;
        
        // Count matching compliments
        for (uint256 i = 1; i <= totalCompliments; i++) {
            if (compliments[i].recipient == user && compliments[i].isActive) {
                count++;
            }
        }
        
        if (offset >= count || limit == 0) {
            return new Compliment ;
        }
        
        uint256 resultSize = (offset + limit > count) ? count - offset : limit;
        Compliment[] memory result = new Compliment[](resultSize);
        
        uint256 found = 0;
        uint256 resultIndex = 0;
        
        for (uint256 i = 1; i <= totalCompliments && resultIndex < resultSize; i++) {
            if (compliments[i].recipient == user && compliments[i].isActive) {
                if (found >= offset) {
                    result[resultIndex] = compliments[i];
                    resultIndex++;
                }
                found++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev Get recent compliments
     * @param limit Number of compliments to return
     */
    function get
/*Added one function suggested by ChatGPT */
