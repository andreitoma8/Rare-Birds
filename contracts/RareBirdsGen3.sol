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

contract RareBirdsGenTwo is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    // Interfaces for ERC20 and ERC721
    IERC20 public rewardsToken;
    IRareBirds public genFour;

    // Address of the Gen. 1 Smart Contract
    address genTwo;

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

    // Price of one NFT
    uint256 public cost;

    // The maximum supply of your collection for sale
    uint256 public maxSupplyBuy;

    // The amount of of tokens minted by buying
    uint256 public mintedFromBuy;

    // The maximum mint amount allowed per transaction
    uint256 public maxMintAmountPerTx;

    // Maximum number of mints from breeding
    uint256 public maxSupplyBree;

    // The amount of tokens minted from breeding
    uint256 public mintedFromBreed;

    // The paused state for minting
    bool public paused = true;

    // The revealed state for Tokens Metadata
    bool public revealed = false;

    // Presale state
    bool public presale = false;

    // The Merkle Root (more info in README file)
    bytes32 internal merkleRoot;

    // Mapping of address to bool that determins wether the address already claimed the whitelist mint
    mapping(address => bool) public whitelistClaimed;

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
    constructor(IERC20 _rewardToken) ERC721("Rare Birds", "BIRDS") {
        rewardsToken = _rewardToken;
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

    // Function called to breed and mint a new egg in Gen. 2 Collection
    function breed(bool _mangoPayment) external {
        require(
            stakers[msg.sender].canBreed == true,
            "You don't have enough staked birds to breed"
        );
        if (_mangoPayment) {
            require(
                block.timestamp >
                    stakers[msg.sender].timeOfBreedingStart + timeToBreedMango,
                "Not enought time passed!"
            );
            // ToDo: Add payment logic here
        } else {
            require(
                block.timestamp >
                    stakers[msg.sender].timeOfBreedingStart + timeToBreedFree,
                "Not enough time passed!"
            );
        }
        genFour.mint();
        stakers[msg.sender].canBreed = false;
    }

    // Modifier that ensures the maximum supply and
    // the maximum amount to mint per transaction
    modifier mintCompliance(uint256 _mintAmount) {
        require(
            _mintAmount > 0 && _mintAmount <= maxMintAmountPerTx,
            "Invalid mint amount!"
        );
        require(
            supply.current() + _mintAmount <= maxSupplyBuy,
            "Max supply exceeded!"
        );
        _;
    }

    // Returns the current supply of the collection
    function totalSupply() public view returns (uint256) {
        return supply.current();
    }

    // Mint function
    function mintFromBreeding() public {
        require(msg.sender == genTwo, "Only Gen 1 SC can mint!");
        mintedFromBreed++;
        require(
            mintedFromBreed <= maxSupplyBree,
            "All the tokens available trough breeding have been minted!"
        );
        _mintLoop(msg.sender, 1);
    }

    // Mint function
    function mint(uint256 _mintAmount)
        public
        payable
        mintCompliance(_mintAmount)
    {
        require(!paused, "The contract is paused!");
        // ToDo: Add payment logic here
        _mintLoop(msg.sender, _mintAmount);
    }

    // The whitelist mint function
    // Can only be called once per address
    // _merkleProof = Hex proof generated by Merkle Tree for whitelist verification,
    //  should be generated by website (more info in README file)
    function whitelistMint(uint256 _mintAmount, bytes32[] calldata _merkleProof)
        public
        payable
        mintCompliance(_mintAmount)
    {
        require(presale, "Presale is not active.");
        require(!whitelistClaimed[msg.sender], "Address has already claimed.");
        require(_mintAmount < 3);
        bytes32 leaf = keccak256(abi.encodePacked((msg.sender)));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid proof"
        );
        whitelistClaimed[msg.sender] = true;
        _mintLoop(msg.sender, _mintAmount);
    }

    // Mint function for owner that allows for free minting for a specified address
    function mintForAddress(uint256 _mintAmount, address _receiver)
        public
        mintCompliance(_mintAmount)
        onlyOwner
    {
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
            ownedTokenIndex < ownerTokenCount &&
            currentTokenId <= (maxSupplyBree + maxSupplyBuy)
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
        genFour = _address;
    }

    // Changes the Revealed State
    function setRevealed(bool _state) public onlyOwner {
        revealed = _state;
    }

    // Set the mint cost of one NFT
    function setCost(uint256 _cost) public onlyOwner {
        cost = _cost;
    }

    // Set the maximum mint amount per transaction
    function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx)
        public
        onlyOwner
    {
        maxMintAmountPerTx = _maxMintAmountPerTx;
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

    // Change paused state of minting for presale
    function setPresale(bool _bool) public onlyOwner {
        presale = _bool;
    }

    // Set the Merkle Root for whitelist verification(more info in README file)
    function setMerkleRoot(bytes32 _newMerkleRoot) public onlyOwner {
        merkleRoot = _newMerkleRoot;
    }

    // Withdraw Mango after sale
    function withdraw() public onlyOwner {
        // ToDo: Add mango withdraw logic here
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
