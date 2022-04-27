// SPDX-License-Identifier: MIT
// Creator: andreitoma8
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IRareBirds.sol";
import "../interfaces/IElementalStones.sol";

contract RareBirdsGenTwo is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    // Interfaces for ERC20 and ERC721
    IERC20 public rewardsToken;
    IRareBirds public genThree;
    IRareBirds public elementalGenOne;
    IElementalStones public elementalStones;

    // Address of the Gen. 1 Smart Contract
    address genOne;

    // Time to hatch without Mango payment
    uint256 public constant timeToHatchFree = 2592000;

    // Time to hatch with Mango payment
    uint256 public constant timeToHatchMango = 604800;

    // Time to breed without Mango payment
    uint256 public constant timeToBreedFree = 2592000;

    // Time to breed with Mango payment
    uint256 public constant timeToBreedMango = 604800;

    // Rewards per hour per token deposited in wei.
    // Rewards are cumulated once every hour.
    uint256 private rewardsPerHour = 100000;

    // Uri for the Gen. 1 Eggs
    // Used in the format: "ipfs://your_uri/".
    string internal uriEggs;

    // Uri for the Gen. 1 Birds
    string internal uriBirds;

    // The format of your metadata files
    string internal uriSuffix = ".json";

    // The URI for your Hidden Metadata
    string internal hiddenMetadataUri;

    // The maximum supply of your collection for sale
    uint256 public maxSupply = 10000;

    // The paused state for minting
    bool public paused = true;

    // The revealed state for Tokens Metadata
    bool public revealed = false;

    // Mapping of tokenID to time of Stake
    mapping(uint256 => uint256) public timeOfStake;

    // Mapping of User Address to Staker info
    mapping(address => Staker) public stakers;

    // Staker info
    struct Staker {
        // Token IDs staked by staker
        uint256[] tokenIdsStaked;
        // Last time of details update for this User
        uint256 timeOfLastUpdate;
        // Calculated, but unclaimed rewards for the User. The rewards are
        // calculated each time the user writes to the Smart Contract
        uint256 unclaimedRewards;
        // User time of last deposit that can be breeded
        uint256 timeOfBreedingStart;
        // Can breed
        bool canBreed;
    }

    // Struct NFTs
    struct NFT {
        // True if Token is a brid, False if Token is an egg
        bool hatched;
        // State of Token Id
        bool staked;
    }

    mapping(uint256 => NFT) nfts;

    // Constructor function that sets name and symbol
    // of the collection, cost, max supply and the maximum
    // amount a user can mint per transaction
    constructor(IERC20 _rewardToken, address _genOne)
        ERC721("Rare Birds Gen. 2", "RB2")
    {
        rewardsToken = _rewardToken;
        genOne = _genOne;
    }

    // Staking function.
    function stake(uint256[] calldata _tokenIds) public nonReentrant {
        if (stakers[msg.sender].tokenIdsStaked.length > 0) {
            uint256 rewards = calculateRewards(msg.sender);
            stakers[msg.sender].unclaimedRewards += rewards;
        }
        for (uint256 i; i < _tokenIds.length; ++i) {
            require(
                ownerOf(_tokenIds[i]) == msg.sender,
                "Can't stake tokens you don't own!"
            );
            nfts[_tokenIds[i]].staked = true;
            stakers[msg.sender].tokenIdsStaked.push(_tokenIds[i]);
            timeOfStake[_tokenIds[i]] = block.timestamp;
        }
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        if (
            stakers[msg.sender].tokenIdsStaked.length > 1 &&
            !stakers[msg.sender].canBreed
        ) {
            // If user has 2 or more birds staked, activate breeding and
            // breeding timer for user.
            uint256 stakedBirds = 0;
            for (
                uint256 i;
                i < stakers[msg.sender].tokenIdsStaked.length;
                ++i
            ) {
                if (
                    nfts[stakers[msg.sender].tokenIdsStaked[i]].hatched == true
                ) {
                    stakedBirds++;
                }
            }
            if (stakedBirds >= 2) {
                stakers[msg.sender].timeOfBreedingStart = block.timestamp;
                stakers[msg.sender].canBreed = true;
            }
        }
    }

    // Check if user has any ERC721 Tokens Staked and if he tried to withdraw,
    // calculate the rewards and store them in the unclaimedRewards and for each
    // ERC721 Token in param: check if msg.sender is the original staker, decrement
    // the amountStaked of the user and transfer the ERC721 token back to them.
    function withdraw(uint256[] memory _tokenIds) external nonReentrant {
        require(
            stakers[msg.sender].tokenIdsStaked.length > 0,
            "You have no tokens staked"
        );
        uint256 rewards = calculateRewards(msg.sender);
        stakers[msg.sender].unclaimedRewards += rewards;
        for (uint256 i; i < _tokenIds.length; ++i) {
            require(
                ownerOf(_tokenIds[i]) == msg.sender,
                "You can only wihtdraw your own tokens!"
            );
            for (
                uint256 j;
                j < stakers[msg.sender].tokenIdsStaked.length;
                ++j
            ) {
                if (stakers[msg.sender].tokenIdsStaked[j] == _tokenIds[i]) {
                    stakers[msg.sender].tokenIdsStaked[j] = stakers[msg.sender]
                        .tokenIdsStaked[
                            stakers[msg.sender].tokenIdsStaked.length - 1
                        ];
                    stakers[msg.sender].tokenIdsStaked.pop();
                }
            }
            nfts[_tokenIds[i]].staked = false;
        }
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        //
        if (stakers[msg.sender].tokenIdsStaked.length < 2) {
            stakers[msg.sender].canBreed = false;
        } else {
            // If user has less than 2 birds staked, deactivate breeding for user.
            uint256 stakedBirds = 0;
            for (
                uint256 i;
                i < stakers[msg.sender].tokenIdsStaked.length;
                ++i
            ) {
                if (
                    nfts[stakers[msg.sender].tokenIdsStaked[i]].hatched == true
                ) {
                    stakedBirds++;
                }
            }
            if (stakedBirds < 2) {
                stakers[msg.sender].canBreed = false;
            }
        }
    }

    // Function called to turn egg into bird
    function hatchEgg(uint256 _tokenId, bool _mangoPayment) external {
        require(nfts[_tokenId].staked == true, "Egg not staked");
        require(!nfts[_tokenId].hatched, "You already have a bird!");
        if (_mangoPayment) {
            require(
                block.timestamp >= timeOfStake[_tokenId] + timeToHatchMango,
                "You need to wait more for egg to hatch!"
            );
            rewardsToken.transferFrom(msg.sender, address(this), 1000 * 10**18);
        } else {
            require(
                block.timestamp >= timeOfStake[_tokenId] + timeToHatchFree,
                "You need to wait more for egg to hatch!"
            );
        }
        nfts[_tokenId].hatched = true;
        // Enable breeding for user if he has 2 or more Birds staked after hatch
        if (
            stakers[msg.sender].tokenIdsStaked.length > 1 &&
            !stakers[msg.sender].canBreed
        ) {
            // If user has 2 or more birds staked, activate breeding and
            // breeding timer for user.
            uint256 stakedBirds = 0;
            for (
                uint256 i;
                i < stakers[msg.sender].tokenIdsStaked.length;
                ++i
            ) {
                if (
                    nfts[stakers[msg.sender].tokenIdsStaked[i]].hatched == true
                ) {
                    stakedBirds++;
                }
            }
            if (stakedBirds >= 2) {
                stakers[msg.sender].timeOfBreedingStart = block.timestamp;
                stakers[msg.sender].canBreed = true;
            }
        }
    }

    // Function that returns true if Token Id is bird and flase if Token Id is egg
    function isBird(uint256 _tokenId) public view returns (bool) {
        return nfts[_tokenId].hatched;
    }

    // The time of stake for Token Id, returns 0 if tokenId is hatched
    function timeOfStartHatch(uint256 _tokenId)
        external
        view
        returns (uint256)
    {
        if (nfts[_tokenId].hatched) {
            return 0;
        } else {
            return timeOfStake[_tokenId];
        }
    }

    // Function that returns the time a user has started the breeding process, for frontend
    function breedingState(address _user)
        external
        view
        returns (bool, uint256)
    {
        return (stakers[_user].canBreed, stakers[_user].timeOfBreedingStart);
    }

    // Function called to breed and mint a new egg in Gen. 2 Collection
    function breed(uint256 _elemental) external {
        require(!paused, "Breeding is paused!");
        require(
            stakers[msg.sender].canBreed == true,
            "You don't have enough staked birds to breed"
        );
        // if (_mangoPayment) {
        //     require(
        //         block.timestamp >
        //             stakers[msg.sender].timeOfBreedingStart + timeToBreedMango,
        //         "Not enought time passed!"
        //     );
        //     // ToDo: Add payment logic here
        // } else {
        require(
            block.timestamp >
                stakers[msg.sender].timeOfBreedingStart + timeToBreedFree,
            "Not enough time passed!"
        );
        // }
        if (_elemental == 0) {
            genThree.mintFromBreeding(msg.sender);
        } else {
            elementalStones.burn(_elemental);
            elementalGenOne.mintFromBreeding(msg.sender);
        }
        stakers[msg.sender].timeOfBreedingStart = block.timestamp;
    }

    // Returns the current supply of the collection
    function totalSupply() public view returns (uint256) {
        return supply.current();
    }

    // Mint function
    function mintFromBreeding(address _to) public payable {
        require(msg.sender == genOne, "Only Gen 1 SC can mint!");
        require(supply.current() + 1 <= maxSupply, "Max supply exceeded!");
        _mintLoop(_to, 1);
    }

    // Mint function for owner that allows for free minting for a specified address
    function mintForAddress(uint256 _mintAmount, address _receiver)
        public
        onlyOwner
    {
        require(
            supply.current() + _mintAmount <= maxSupply,
            "Max supply exceeded!"
        );
        _mintLoop(_receiver, _mintAmount);
    }

    // Calculate rewards for the msg.sender, check if there are any rewards
    // claim, set unclaimedRewards to 0 and transfer the ERC20 Reward token
    // to the user.
    function claimRewards() external nonReentrant {
        uint256 rewards = calculateRewards(msg.sender) +
            stakers[msg.sender].unclaimedRewards;
        require(rewards > 0, "You have no rewards to claim");
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        stakers[msg.sender].unclaimedRewards = 0;
        rewardsToken.transferFrom(address(this), msg.sender, rewards);
    }

    // Returns the information of _user address deposit:
    // the amount of tokens staked, the rewards available
    // for withdrawal and the Token Ids staked
    function userStakeInfo(address _user)
        public
        view
        returns (uint256 _availableRewards, uint256[] memory _tokenIdsStaked)
    {
        return (availableRewards(_user), stakers[_user].tokenIdsStaked);
    }

    // Returns the Token Id for Tokens owned by the specified address
    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = 1;
        uint256 ownedTokenIndex = 0;

        while (
            ownedTokenIndex < ownerTokenCount && currentTokenId <= maxSupply
        ) {
            address currentTokenOwner = ownerOf(currentTokenId);

            if (currentTokenOwner == _owner) {
                ownedTokenIds[ownedTokenIndex] = currentTokenId;

                ownedTokenIndex++;
            }

            currentTokenId++;
        }

        return ownedTokenIds;
    }

    // Returns the Token URI with Metadata for specified Token Id
    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        string memory currentBaseURI = _baseURI(_tokenId);
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        uriSuffix
                    )
                )
                : "";
    }

    // Set the next gen SC interface:
    function setNextGen(IRareBirds _address) public onlyOwner {
        genThree = _address;
    }

    // Set the Elemental Stones Smart Contract
    function setElementalStones(IElementalStones _address) external onlyOwner {
        elementalStones = _address;
    }

    // Set the Elemental Birds Gen 1 Smart Contract
    function setElementalBirdsGen1(IRareBirds _address) external onlyOwner {
        elementalGenOne = _address;
    }

    // Changes the Revealed State
    function setRevealed(bool _state) public onlyOwner {
        revealed = _state;
    }

    // Set the hidden metadata URI
    function setHiddenMetadataUri(string memory _hiddenMetadataUri)
        public
        onlyOwner
    {
        hiddenMetadataUri = _hiddenMetadataUri;
    }

    // Set the URI of your IPFS/hosting server for the metadata folder.
    // Used in the format: "ipfs://your_uri/".
    function setUris(string memory _uriEggs, string memory _uriBirds)
        public
        onlyOwner
    {
        uriEggs = _uriEggs;
        uriBirds = _uriBirds;
    }

    // Set the uri sufix for your metadata file type
    function setUriSuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    // Change paused state for main minting
    function setPaused(bool _state) public onlyOwner {
        paused = _state;
    }

    // Withdraw Mango after sale
    function withdraw(uint256 _amount) public onlyOwner {
        uint256 maxAmount = rewardsToken.balanceOf(address(this));
        require(_amount <= maxAmount, "You tried to withdraw too much Mingo");
        rewardsToken.transferFrom(address(this), owner(), _amount);
    }

    // Helper function
    function _mintLoop(address _receiver, uint256 _mintAmount) internal {
        for (uint256 i = 0; i < _mintAmount; i++) {
            supply.increment();
            _safeMint(_receiver, supply.current());
        }
    }

    // Helper function
    function _baseURI(uint256 _tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        if (nfts[_tokenId].hatched) {
            return uriBirds;
        } else {
            return uriEggs;
        }
    }

    // Return available Mango rewards for user.
    function availableRewards(address _user) internal view returns (uint256) {
        uint256 _rewards = stakers[_user].unclaimedRewards +
            calculateRewards(_user);
        return _rewards;
    }

    // Calculate rewards for param _staker by calculating the time passed
    // since last update in hours and mulitplying it to ERC721 Tokens Staked
    // and rewardsPerHour.
    function calculateRewards(address _staker)
        internal
        view
        returns (uint256 _rewards)
    {
        return (((
            ((block.timestamp - stakers[_staker].timeOfLastUpdate) *
                stakers[msg.sender].tokenIdsStaked.length)
        ) * rewardsPerHour) / 3600);
    }

    // Just because you never know
    receive() external payable {}

    // Override to block transfers for staked Tokens
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(!nfts[tokenId].staked, "You can't transfer staked tokens!");
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
