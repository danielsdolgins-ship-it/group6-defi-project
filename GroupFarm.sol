// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract GroupFarm {
    IERC20 public rewardToken;
    uint256 public duration = 120 minutes;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public rewardRatePerPool;
    bool public campaignStarted;

    struct Pool {
        IERC20 lpToken;
        uint256 totalStaked;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
    }

    Pool[] public pools;

    mapping(address => mapping(uint256 => uint256)) public balances;
    mapping(address => mapping(uint256 => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(uint256 => uint256)) public rewards;

    // Constructor requires the GROUP6 token address and the two v2 LP token addresses
    constructor(address _rewardToken, address _lpToken0, address _lpToken1) {
        rewardToken = IERC20(_rewardToken);
        
        pools.push(Pool({
            lpToken: IERC20(_lpToken0),
            totalStaked: 0,
            rewardPerTokenStored: 0,
            lastUpdateTime: 0
        }));
        
        pools.push(Pool({
            lpToken: IERC20(_lpToken1),
            totalStaked: 0,
            rewardPerTokenStored: 0,
            lastUpdateTime: 0
        }));
        
        // 40,000 tokens per pool over 120 minutes
        rewardRatePerPool = (40000 * 10**18) / duration;
    }

    modifier updateReward(uint256 poolId, address account) {
        Pool storage pool = pools[poolId];
        pool.rewardPerTokenStored = rewardPerToken(poolId);
        pool.lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account][poolId] = earned(account, poolId);
            userRewardPerTokenPaid[account][poolId] = pool.rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        if (!campaignStarted) return 0;
        return block.timestamp < endTime ? block.timestamp : endTime;
    }

    function rewardPerToken(uint256 poolId) public view returns (uint256) {
        Pool storage pool = pools[poolId];
        if (pool.totalStaked == 0 || !campaignStarted) {
            return pool.rewardPerTokenStored;
        }
        return pool.rewardPerTokenStored + (
            ((lastTimeRewardApplicable() - pool.lastUpdateTime) * rewardRatePerPool * 1e18) / pool.totalStaked
        );
    }

    function earned(address account, uint256 poolId) public view returns (uint256) {
        Pool storage pool = pools[poolId];
        return ((balances[account][poolId] * (rewardPerToken(poolId) - userRewardPerTokenPaid[account][poolId])) / 1e18) + rewards[account][poolId];
    }

    function startSession() external {
        require(!campaignStarted, "Campaign already started");
        // Enforces that the contract holds the required 80,000 GROUP6 budget
        require(rewardToken.balanceOf(address(this)) >= 80000 * 10**18, "Contract not fully funded");
        
        campaignStarted = true;
        startTime = block.timestamp;
        endTime = startTime + duration;
        
        for(uint i = 0; i < pools.length; i++) {
            pools[i].lastUpdateTime = startTime;
        }
    }

    function stake(uint256 poolId, uint256 amount) external updateReward(poolId, msg.sender) {
        require(campaignStarted, "Campaign not active");
        require(amount > 0, "Cannot stake 0");
        
        Pool storage pool = pools[poolId];
        pool.totalStaked += amount;
        balances[msg.sender][poolId] += amount;
        pool.lpToken.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 poolId, uint256 amount) external updateReward(poolId, msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        
        Pool storage pool = pools[poolId];
        pool.totalStaked -= amount;
        balances[msg.sender][poolId] -= amount;
        pool.lpToken.transfer(msg.sender, amount);
    }

    function claim(uint256 poolId) public updateReward(poolId, msg.sender) {
        uint256 reward = rewards[msg.sender][poolId];
        if (reward > 0) {
            rewards[msg.sender][poolId] = 0;
            rewardToken.transfer(msg.sender, reward);
        }
    }

    function claimAll() external {
        for(uint i = 0; i < pools.length; i++) {
            claim(i);
        }
    }
}