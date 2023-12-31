// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {NftContract} from "./NftContract.sol";

contract PresaleContract is Pausable, Ownable {
    uint256 public perRequest = 1;
    mapping(uint256 => mapping(address => uint256)) public addressMintedBalance;

    uint256 public minHoldMembership;

    NftContract private nftContract;
    ERC721 private membershipContract;
    address private nftContractAddress;
    address private membershipContractAddress;

    struct TokenConfig {
        uint256 price;
        uint256 maxSupply;
        uint256 mintedCount;
        uint256 minTokenId;
        uint256 maxTokenId;
        uint256 mintStartBlock;
        uint256 mintEndBlock;
        uint256 perAddress;
        bytes32 merkleRoot;
    }

    mapping(uint256 => TokenConfig) public tokenConfigs; // 토큰 타입별 정보 매핑

    constructor(
        address _initialOwner,
        address _nftContract,
        address _membershipContract
    ) {
        _transferOwnership(_initialOwner);
        nftContractAddress = _nftContract;
        nftContract = NftContract(_nftContract);
        if (_membershipContract != address(0)) {
            membershipContractAddress = _membershipContract;
            membershipContract = ERC721(_membershipContract);
            minHoldMembership = 1;
        }
    }

    function setMembership(address _membershipContract) external onlyOwner {
        membershipContractAddress = _membershipContract;
        membershipContract = ERC721(_membershipContract);
    }

    // 토큰 타입별 정보 등록
    function setTokenConfig(
        uint256 _tokenType,
        uint256 _price,
        uint256 _maxSupply,
        uint256 _minTokenId,
        uint256 _maxTokenId,
        uint256 _mintStartBlock,
        uint256 _mintEndBlock,
        uint256 _perAddress,
        bytes32 _merkleRoot
    ) external onlyOwner {
        require(_price > 0, "Price must be greater than zero");
        require(_maxSupply > 0, "Max supply must be greater than zero");
        require(tokenConfigs[_tokenType].price == 0, "Already set");

        tokenConfigs[_tokenType] = TokenConfig(
            _price,
            _maxSupply,
            0,
            _minTokenId,
            _maxTokenId,
            _mintStartBlock,
            _mintEndBlock,
            _perAddress,
            _merkleRoot
        );
    }

    function endTokenConfig(uint256 _tokenType) external onlyOwner {
        require(tokenConfigs[_tokenType].price > 0, "Not yet set");
        TokenConfig storage tokenConfig = tokenConfigs[_tokenType];
        tokenConfig.maxSupply = tokenConfig.mintedCount;
    }

    function setMinHoldMembership(uint256 count) public onlyOwner {
        minHoldMembership = count;
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        return ERC721(nftContractAddress).balanceOf(owner);
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return ERC721(nftContractAddress).ownerOf(tokenId);
    }

    function maxSupply(
        uint256 _tokenType
    ) public view virtual returns (uint256) {
        TokenConfig storage tokenConfig = tokenConfigs[_tokenType];
        return tokenConfig.maxSupply;
    }

    function totalSupply(
        uint256 _tokenType
    ) public view virtual returns (uint256) {
        TokenConfig storage tokenConfig = tokenConfigs[_tokenType];
        return tokenConfig.mintedCount;
    }

    // event MintRoundBlockChanged(uint256 startBlockTime, uint256 endBlockTime);
    event Withdraw(uint256 amount);
    event NFTMinted(address minter, uint256 nftId);

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // NFT 민팅
    function whitelistMintTo(
        uint256 _tokenType,
        address to,
        uint256 _quantity,
        bytes32[] calldata _merkleProof
    ) external payable whenNotPaused {
        TokenConfig storage tokenConfig = tokenConfigs[_tokenType];

        bytes32 node = keccak256(abi.encodePacked(to));
        require(
            MerkleProof.verifyCalldata(
                _merkleProof,
                tokenConfig.merkleRoot,
                node
            ) == true,
            "user is not whitelisted"
        );

        require(tokenConfig.price > 0, "Invalid token price");
        require(_quantity <= perRequest, "Invalid quantity");
        require(
            msg.sender == owner() || msg.value == tokenConfig.price * _quantity,
            "Incorrect amount sent"
        );
        require(
            block.timestamp >= tokenConfig.mintStartBlock &&
                block.timestamp <= tokenConfig.mintEndBlock,
            "Not available now"
        );
        require(
            tokenConfig.mintedCount + _quantity <= tokenConfig.maxSupply,
            "Token supply exceeded"
        );
        require(
            addressMintedBalance[_tokenType][msg.sender] + _quantity <=
                tokenConfig.perAddress,
            "Per address exceeded"
        );
        require(
            minHoldMembership == 0 ||
                membershipContract.balanceOf(to) >= minHoldMembership,
            "not enough membership nfts"
        );

        for (uint256 i = 0; i < _quantity; i++) {
            uint256 nftId = getNextTokenId(_tokenType);
            nftContract.safeMint(to, nftId);

            emit NFTMinted(to, nftId);
        }
        tokenConfig.mintedCount += _quantity;
        addressMintedBalance[_tokenType][msg.sender] += _quantity;
    }

    // 다음 토큰 ID 가져오기
    function getNextTokenId(
        uint256 _tokenType
    ) internal view returns (uint256) {
        TokenConfig storage tokenConfig = tokenConfigs[_tokenType];
        uint256 nextTokenId = tokenConfig.minTokenId + tokenConfig.mintedCount;

        require(
            nextTokenId <= tokenConfig.maxTokenId,
            "Token ID range exceeded"
        );

        return nextTokenId;
    }

    function setMintRoundBlock(
        uint256 startBlock,
        uint256 endBlock,
        uint256 tokenType
    ) public onlyOwner {
        TokenConfig storage tokenConfig = tokenConfigs[tokenType];

        tokenConfig.mintStartBlock = startBlock;
        tokenConfig.mintEndBlock = endBlock;
        // emit MintRoundBlockChanged(_mintStartBlock, _mintEndBlock);
    }

    function mintRoundBlock(
        uint256 tokenType
    ) public view returns (uint256, uint256) {
        TokenConfig storage tokenConfig = tokenConfigs[tokenType];
        return (tokenConfig.mintStartBlock, tokenConfig.mintEndBlock);
    }

    function setPerRequest(uint256 amount) public onlyOwner {
        perRequest = amount;
    }

    function withdraw() public payable onlyOwner {
        emit Withdraw(address(this).balance);
        (bool os, ) = payable(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(os);
    }
}
