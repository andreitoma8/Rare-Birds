// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "../interfaces/IRareBirds.sol";

contract ElementalStones is ERC721, Ownable, ReentrancyGuard, ERC721Burnable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    // Interfaces for ERC20 and ERC721
    IERC20 public rewardsToken;
    IRareBirds public genOne;

    // The URI of your IPFS/hosting server for the metadata folder.
    // Used in the format: "ipfs://your_uri/".
    string internal uri;

    // The format of your metadata files
    string internal uriSuffix = ".json";

    // The URI for your Hidden Metadata
    string internal hiddenMetadataUri;

    // Price of one NFT
    uint256 public cost;

    // The maximum supply of your collection
    uint256 public maxSupply = 10000;

    // The maximum mint amount allowed per transaction
    uint256 public maxMintAmountPerTx = 10;

    // Time to breed without Mango payment
    uint256 public constant timeToBreedFree = 2592000;

    // Time to breed with Mango payment
    uint256 public constant timeToBreedMango = 604800;

    // Rewards per hour per token deposited in wei.
    // Rewards are cumulated once every hour.
    uint256 private rewardsPerHour = 100000;

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

    // Mapping of supply for each type
    mapping(uint256 => uint256) public typeSupply;

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

    // Mapping of tokenID to time of Stake
    mapping(uint256 => uint256) public timeOfStake;

    // Constructor function that sets name and symbol
    // of the collection
    constructor() ERC721("Elemental Stones", "STONE") {}

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
            // nfts[_tokenIds[i]].staked = true;
            stakers[msg.sender].tokenIdsStaked.push(_tokenIds[i]);
            timeOfStake[_tokenIds[i]] = block.timestamp;
        }
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        stakers[msg.sender].timeOfBreedingStart = block.timestamp;
        // ToDo: Add transger logic here for birds + lock/burn elemental stone
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
        // uint256 rewards = calculateRewards(msg.sender);
        // stakers[msg.sender].unclaimedRewards += rewards;
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
        }
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        // ToDo: Add logic for token transfer back to owner
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
        genOne.mintFromBreeding();
        stakers[msg.sender].canBreed = false;
    }

    // Calculate rewards for param _staker by calculating the time passed
    // since last update in hours and mulitplying it to ERC721 Tokens Staked
    // and rewardsPerHour.
    function calculateRewards(address _staker) internal view returns (uint256) {
        uint256 _rewards = (((
            ((block.timestamp - stakers[_staker].timeOfLastUpdate) *
                stakers[msg.sender].tokenIdsStaked.length)
        ) * rewardsPerHour) / 3600);
        if (_rewards > rewardsPerHour * timeToBreedFree) {
            return rewardsPerHour * timeToBreedFree;
        } else {
            return _rewards;
        }
    }

    // Set the next gen SC interface:
    function setNextGen(IRareBirds _address) public onlyOwner {
        genOne = _address;
    }

    // Modifier that ensures the maximum supply and
    // the maximum amount to mint per transaction
    modifier mintCompliance(uint256 _mintAmount, uint256 _type) {
        require(
            _mintAmount > 0 && _mintAmount <= maxMintAmountPerTx,
            "Invalid mint amount!"
        );
        require(
            supply.current() + _mintAmount <= maxSupply,
            "Max supply exceeded!"
        );
        require(
            typeSupply[_type] <= 2500,
            "Max supply excedeed for this type!"
        );
        require(_type > 0 && _type < 5, "Non-existent type");
        _;
    }

    // Returns the current supply of the collection
    function totalSupply() public view returns (uint256) {
        return supply.current();
    }

    // Mint function
    function mint(uint256 _mintAmount, uint256 _type)
        public
        payable
        mintCompliance(_mintAmount, _type)
    {
        require(!paused, "The contract is paused!");
        require(msg.value >= cost * _mintAmount, "Insufficient funds!");

        _mintLoop(msg.sender, _mintAmount, _type);
    }

    // The whitelist mint function
    // Can only be called once per address
    // _merkleProof = Hex proof generated by Merkle Tree for whitelist verification,
    //  should be generated by website (more info in README file)
    function whitelistMint(
        uint256 _mintAmount,
        uint256 _type,
        bytes32[] calldata _merkleProof
    ) public payable mintCompliance(_mintAmount, _type) {
        require(presale, "Presale is not active.");
        require(!whitelistClaimed[msg.sender], "Address has already claimed.");
        require(_mintAmount < 3);
        bytes32 leaf = keccak256(abi.encodePacked((msg.sender)));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid proof"
        );
        whitelistClaimed[msg.sender] = true;
        _mintLoop(msg.sender, _mintAmount, _type);
    }

    // Mint function for owner that allows for free minting for a specified address
    function mintForAddress(
        uint256 _mintAmount,
        uint256 _type,
        address _receiver
    ) public mintCompliance(_mintAmount, _type) onlyOwner {
        _mintLoop(_receiver, _mintAmount, _type);
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

        if (revealed == false) {
            return hiddenMetadataUri;
        }

        string memory currentBaseURI = _baseURI();
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
    function setUri(string memory _uri) public onlyOwner {
        uri = _uri;
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

    // Withdraw ETH after sale
    function withdraw() public onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    // Helper function
    function _mintLoop(
        address _receiver,
        uint256 _mintAmount,
        uint256 _type
    ) internal {
        for (uint256 i = 0; i < _mintAmount; i++) {
            supply.increment();
            typeSupply[_type]++;
            _safeMint(_receiver, typeSupply[_type] + ((_type - 1) * 2500));
        }
    }

    // Helper function
    function _baseURI() internal view virtual override returns (string memory) {
        return uri;
    }

    // Just because you never know
    receive() external payable {}
}
