// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract RareBirds is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    // Interfaces for ERC20 and ERC721
    IERC20 public rewardsToken;
    IERC721 public genOne;

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
    string internal uirBirds;

    // The format of your metadata files
    string internal uriSuffix = ".json";

    // The URI for your Hidden Metadata
    string internal hiddenMetadataUri;

    // The maximum supply of your collection
    uint256 public maxSupply;

    // The revealed state for Tokens Metadata
    bool public revealed = false;

    // Mapping of tokenID to time of Stake
    mapping(uint256 => uint256) public timeOfStake;

    // Mapping of User Address to Staker info
    mapping(address => Staker) public stakers;

    // Mapping of User Address to Breeder struct
    mapping(address => Breeder) public breeders;

    // Mapping of token
    mapping(uint256 => bool) public hatched;

    // Staked state for Token ID
    mapping(uint256 => bool) public staked;

    // Staker info
    struct Staker {
        // Token IDs staked by staker
        uint256[] tokenIdsStaked;
        // Last time of details update for this User
        uint256 timeOfLastUpdate;
        // Calculated, but unclaimed rewards for the User. The rewards are
        // calculated each time the user writes to the Smart Contract
        uint256 unclaimedRewards;
    }

    struct Breeder {
        // Token Id of mom
        uint256 mom;
        // Token Id of dad
        uint256 dad;
        // Time of breeding start
        uint256 breedingStart;
    }

    // Constructor function that sets name and symbol
    // of the collection, cost, max supply and the maximum
    // amount a user can mint per transaction
    constructor(IERC20 _rewardToken, IERC721 _genOne)
        ERC721("Rare Birds", "BIRDS")
    {
        rewardsToken = _rewardToken;
        genOne = _genOne;
    }

    // Staking function
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
            staked[_tokenIds[i]] = true;
            stakers[msg.sender].tokenIdsStaked.push(_tokenIds[i]);
            timeOfStake[_tokenIds[i]] = block.timestamp;
        }
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
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
            staked[_tokenIds[i]] = false;
        }
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
    }

    function hatchEgg(uint256 _tokenId, bool _mangoPayment) external {
        require(staked[_tokenId] == true, "Egg not staked");
        require(!hatched[_tokenId], "You already have a bird!");
        if (_mangoPayment) {
            require(
                block.timestamp > timeOfStake[_tokenId] + timeToHatchMango,
                "You need to wait more for egg to hatch!"
            );
            // ToDo: Add payment logic here
        } else {
            require(
                block.timestamp > timeOfStake[_tokenId] + timeToHatchFree,
                "You need to wait more for egg to hatch!"
            );
        }
        hatched[_tokenId] = true;
    }

    // Returns the current supply of the collection
    function totalSupply() public view returns (uint256) {
        return supply.current();
    }

    // Stake two Gen 1 Birds to recieve a Gen. 2 Egg.
    function breed(uint256 _tokenIdMom, uint256 _tokenIdDad) external {
        //ToDo: Add breeding logic here
        genOne.transferFrom(msg.sender, address(this), _tokenIdMom);
        genOne.transferFrom(msg.sender, address(this), _tokenIdDad);
        breeders[msg.sender].mom = _tokenIdMom;
        breeders[msg.sender].dad = _tokenIdDad;
        breeders[msg.sender].breedingStart = block.timestamp;
        _mintLoop(msg.sender, 1);
    }

    // Call function to finish breeding and mint the egg
    function mintEgg(bool _mangoPayment) external {
        if (_mangoPayment) {
            require(
                block.timestamp >=
                    breeders[msg.sender].breedingStart + timeToBreedMango
            );
            //ToDo: Add payment logic here
        } else {
            require(
                block.timestamp >=
                    breeders[msg.sender].breedingStart + timeToBreedFree
            );
        }
        _mintLoop(msg.sender, 1);
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
        // ToDo: Add payment logic here
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
        uirBirds = _uriBirds;
    }

    // Set the uri sufix for your metadata file type
    function setUriSuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    // Withdraw ETH after sale
    function withdraw() public onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
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
        if (hatched[_tokenId]) {
            return uirBirds;
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
        require(!staked[tokenId], "You can't transfer staked tokens!");
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
