pragma solidity >=0.6.0 <0.7.0;

import "./github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol"

contract SFRevShareNFTAuction is ERC721 {

address public NFTContract;
uint public sourceTokenId;
address public creator;

uint256 public totalNFTcopies;
// winLength is the number of blocks that a user must be the highBidder to win the auction;
uint256 public winLength;

struct Auction {
    uint256 generation;
    uint256 startTime;
    uint256 lastBidTime;
    uint256 winLength;
    uint256 highBid;
    address payable owner;
    address payable highBidder;
    address payable prevHighBidder;
}

address[] public revShareRecipients;

uint256 public totalAuctions;

mapping (uint256 => Auction) public tokenIdToAuction;
mapping (uint256 => RevShare) public tokenIdToRevShare;
mapping (uint256 => address) public owners; 

event newAuction(uint256 id, uint256 startTime);
event auctionWon(uint256 id, address indexed winner);

constructor(address _NFTContract, uint _sourceTokenId) public {
    NFTContract = _NFTContract;
    sourceTokenId = _sourceTokenId;
    creator = msg.sender;
    totalNFTcopies = 1;
    winLength = 180 seconds;
    revShareRecipients.push(creator);
}
    
    function scheduleAuction(uint memory tokenId, uint256 memory startTime) public returns (uint256) {
      ERC721 nft = ERC721(NFTContract);
      require(msg.sender = nft.ownerOf(tokenId), "only the NFT's owner can start the auction");
      require(startTime >= now, "the start time must be in the future");
      
      totalAuctions.increment();
      
      Auction storage _auction = tokenIdToAuction[tokenId];
      
      _auction.generation = _auction.generation++;
      _auction.startTime = startTime;
      _auction.lastBidTime = 0;
      _auction.winLength = winLength;
      _auction.highBid = 0;
      _auction.owner = msg.sender;
      _auction.highBidder = "0x00";
      _auction.prevHighBidder = "0x00";


      emit newAuction(_auction.tokenId, _auction.startTime);

      return _auction.generation;
    }

    function bid(uint memory tokenId, uint memory bidAmt) public payable returns (uint256, uint256, address) {
        Auction storage _auction = tokenIdToAuction[tokenId];
       
        require(_auction.startTime <= now, "the auction hasn't started yet");
        // NEED TO FIGURE OUT HOW TO DO THIS WITH SUPERFLUID ERC20
        require(msg.value = bidAmt, "you haven't sent the correct value");
        require(bidAmt > _auction.highBid, "you must bid more than the current high bid");
        require(!(now < _auction.lastBidTime + _auction.winLength), "this auction is already over");
        
        // highBidder creates new SuperFluid flows
        for (i = 0; i < revShareRecipients.length; ++i) {
        
            sf.host.callAgreement(sf.agreements.cfa.address, sf.agreements.cfa.contract.methods.createFlow
                (daix.address, revShareRecipients[i], bidAmt / revShareRecipients.length, "0x").encodeABI(), { from: msg.sender })
        }
    
        // new highBidder should stop previous highBidder's SuperFluid flows
        for (i = 0; i < revShareRecipients.length; ++i) {
        
            sf.host.callAgreement(sf.agreements.cfa.address, sf.agreements.cfa.contract.methods.deleteFlow
                (daix.address, _auction.prevHighBidder, revShareRecipients[i], bidAmt / revShareRecipients.length, "0x").encodeABI(), { from: _auction.prevHighBidder })
    
        _auction.highBid = bidAmt;
        _auction.highBidder = _auction.prevHighBidder;
        _auction.highBidder = msg.sender;
        _auction.lastBidTime = now;
        
        return _auction.highBid, _auction.lastBidTime, _auction.highBidder);
    }
    
    function claimNFT(uint tokenId) public returns (bool) {
        Auction storage _auction = tokenIdToAuction[tokenId];
        require((now > _auction.lastBidTime + _auction.winLength), "this auction isn't over yet");
        require(msg.sender = _auction.highBidder, "only the auction winner can claim");
        
        // claiming an NFT shuts off the SuperFluid flow
        for (i = 0; i < revShareRecipients.length; ++i) {
            
            sf.host.callAgreement(sf.agreements.cfa.address, sf.agreements.cfa.contract.methods.deleteFlow
                (daix.address, msg.sender, revShareRecipients[i], bidAmt / revShareRecipients.length, "0x").encodeABI(), { from: msg.sender })
        }
        
        // auction winner becomes the new owner
        ERC721 erc721Token = ERC721(tokenContract);
        erc721Token.safeTransferFrom(owners[tokenId], msg.sender, tokenId);
        _auction.owner = msg.sender;
        _auction.parentTokenId = tokenId -1;
        owners[tokenId] = msg.sender;
                
        // claiming an NFT automatically mints a childNFT and starts a new auction
        uint childNFT = _mintChildNFT(tokenId);
        revShareRecipients.push(msg.sender);
        startAuction(childNFT, now);
        
        emit auctionWon(tokenId, msg.sender);
        emit newAuction(childNFT, now);
        return true;
    }
    
    function _mintChildNFT(uint tokenId) private returns (uint256) {
        ERC721 erc721Token = ERC721(tokenContract);
        childTokenId = tokenId + 1; 
        erc721Token._safeMint(msg.sender, childTokenId);
        return childtokenId;
    }
 }
