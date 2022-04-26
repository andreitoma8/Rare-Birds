// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

contract ElementalStones is ERC721, Ownable, ReentrancyGuard, ERC721Burnable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    // Interfaces for ERC20 and ERC721
    IERC20 public rewardsToken;

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

    // Mapping of user to deposits
    mapping(address => uint256) public userWithdrawTime;

    // Mapping of user to deposit state
    mapping(address => bool) hasDeposit;

    // Constructor function that sets name and symbol
    // of the collection
    constructor(IERC20 _address) ERC721("Elemental Stones", "STONE") {
        rewardsToken = _address;
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
    function mint(
        uint256 _mintAmount,
        uint256 _type,
        bool _lock
    ) public payable mintCompliance(_mintAmount, _type) {
        require(!paused, "The contract is paused!");
        require(msg.value >= cost * _mintAmount, "Insufficient funds!");
        if (_lock) {
            rewardsToken.transferFrom(
                msg.sender,
                address(this),
                50000 * 10**18
            );
            userWithdrawTime[msg.sender] = block.timestamp + 2592000;
            hasDeposit[msg.sender] = true;
            _mintLoop(msg.sender, _mintAmount, _type);
        } else {
            rewardsToken.transferFrom(msg.sender, address(this), 6000 * 10**18);
            _mintLoop(msg.sender, _mintAmount, _type);
        }
    }

    function withdrawMingo() external nonReentrant {
        require(hasDeposit[msg.sender], "You have no locked Mingo!");
        require(
            block.timestamp > userWithdrawTime[msg.sender],
            "You can't unlock your Mingo yet!"
        );
        hasDeposit[msg.sender] = false;
        rewardsToken.transferFrom(address(this), msg.sender, 50000 * 10**18);
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

    // Withdraw Mango after sale
    function withdraw(uint256 _amount) public onlyOwner {
        uint256 maxAmount = rewardsToken.balanceOf(address(this));
        require(_amount <= maxAmount, "You tried to withdraw too much Mingo");
        rewardsToken.transferFrom(address(this), owner(), _amount);
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
