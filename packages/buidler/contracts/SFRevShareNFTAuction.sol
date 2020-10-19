pragma solidity >=0.6.0 <0.7.0;

import "../../github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../../github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
// import superfluid CFA and IDA contracts

contract SFRevShareNFTAuction is ERC721, IERC721Receiver {

ERC721 public NFTContract;
uint public sourceTokenId;
address payable public creator;
uint256[] public childNFTs;
// winLength is the number of seconds that a user must be the highBidder to win the auction;
uint256 public winLength;

struct Auction {
    uint256 generation;
    uint256 startTime;
    uint256 lastBidTime;
    uint256 winLength;
    uint256 highBid;
    uint256[] bids;
    address payable owner;
    address payable highBidder;
    address[] bidders; 
    address payable prevHighBidder;
}

address[] public revShareRecipients;
uint[] public ownerRevShares;

uint256 public totalAuctions;

mapping (uint256 => Auction) public tokenIdToAuction;
mapping (uint256 => address) public owners; 

event newAuction(uint256 id, uint256 startTime);
event auctionWon(uint256 id, address indexed winner);

constructor(bytes32 _name, bytes32 _symbol, address _NFTContract, uint _sourceTokenId) public {
    require(_NFTContract != address(0) && _NFTContract != address(this));
    name = _name;
    symbol = _symbol;
    NFTContract = ERC721(address(_NFTContract));
    sourceTokenId = _sourceTokenId;
    creator = msg.sender;
    winLength = 180 seconds;
    revShareRecipients.push(creator);
    ownerRevShares.push(100*10**18);
}
    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));   
    }
    
    
    function firstAuction(uint256 startTime) external returns (uint256) {
    // getting weird TypeError on next line "Expression has to be an lvalue"
    //   require(NFTContract.ownerOf(sourceTokenId) = msg.sender, "only the NFT's owner can start the auction");
      require(startTime >= now, "the start time must be in the future");
      
      totalAuctions++;
      
      NFTContract.safeTransferFrom(msg.sender, address(this), sourceTokenId);
      Auction storage _auction = tokenIdToAuction[sourceTokenId];
      
      _auction.generation = _auction.generation++;
      _auction.startTime = startTime;
      _auction.lastBidTime = 0;
      _auction.winLength = winLength;
      _auction.highBid = 0;
      _auction.owner = msg.sender;
      _auction.highBidder = address(0);
      _auction.prevHighBidder = address(0);
      
      // creating the first auction creates an income distribution agreement index
      sf.host.callAgreement(sf.agreements.ida.address, sf.agreements.ida.contract.methods.createIndex
        (daix.address, sourceTokenId, "0x").encodeABI(), { from: address(this) })
        
      uint creatorRevShares = ownerRevShares[0];
      
      // creating the first auction adds the creator to the income distribution agreement subscribers 
      sf.host.callAgreement(sf.agreements.ida.address, sf.agreements.ida.contract.methods.updateSubscription
        (daix.address, sourceTokenId, msg.sender, creatorRevShares, "0x").encodeABI(), { from: address(this) })

      emit newAuction(sourceTokenId, _auction.startTime);

      return _auction.generation;
    }
    
    function _nextAuction(uint tokenId) private returns (uint256) {
      
      totalAuctions++;
      
      NFTContract.safeTransferFrom(msg.sender, address(this), tokenId);
      Auction storage _auction = tokenIdToAuction[tokenId];
      
      _auction.generation = _auction.generation++;
      _auction.startTime = now;
      _auction.lastBidTime = 0;
      _auction.winLength = winLength;
      _auction.highBid = 0;
      _auction.owner = msg.sender;
      _auction.highBidder = address(0);
      _auction.prevHighBidder = address(0);


      emit newAuction(tokenId, _auction.startTime);

      return _auction.generation;
    }

    function bid(uint tokenId, uint bidAmt) public payable returns (uint256, uint256, address) {
        Auction storage _auction = tokenIdToAuction[tokenId];
       
        require(_auction.startTime <= now, "the auction hasn't started yet");
        //Need to figure out how to convert bidAmt to ERC20

        require(bidAmt > _auction.highBid, "you must bid more than the current high bid");
        require(!(now < _auction.lastBidTime + _auction.winLength), "this auction is already over");
        
        // highBidder creates new SuperFluid constant flow agreement
        sf.host.callAgreement(sf.agreements.cfa.address, sf.agreements.cfa.contract.methods.createFlow
           (daix.address, address(this), bidAmt, "0x").encodeABI(), { from: msg.sender })
        
        // new highBidder should stop previous highBidder's SuperFluid constant flow agreement
        sf.host.callAgreement(sf.agreements.cfa.address, sf.agreements.cfa.contract.methods.deleteFlow
           (daix.address, _auction.prevHighBidder, address(this), _auction.highBid, "0x").encodeABI(), { from: address(this) })
           
        _auction.highBid = bidAmt;
        _auction.bids.push(bidAmt);
        _auction.highBidder = _auction.prevHighBidder;
        _auction.highBidder = msg.sender;
        _auction.bidders.push(msg.sender);
        _auction.lastBidTime = now;
        
        return (_auction.highBid, _auction.lastBidTime, _auction.highBidder);
    }
    
    function claimNFT(uint tokenId) public returns (bool) {
        Auction storage _auction = tokenIdToAuction[tokenId];
        require((now > _auction.lastBidTime + _auction.winLength), "this auction isn't over yet");
        
        // getting weird TypeError on next line "Expression has to be an lvalue"
        require(msg.sender = _auction.highBidder, "only the auction winner can claim");
        
        // claiming NFT deletes the winner's SuperFluid constant flow agreement    
        sf.host.callAgreement(sf.agreements.cfa.address, sf.agreements.cfa.contract.methods.deleteFlow
            (daix.address, msg.sender, address(this), bidAmt, "0x").encodeABI(), { from: msg.sender })
        
        // auction winner becomes the new owner
        NFTContract.safeTransferFrom(address(this), msg.sender, tokenId);
        _auction.owner = msg.sender;
        owners[tokenId] = msg.sender;
                
        // claiming an NFT automatically updates the revenue shares array
        _updateRevShares(msg.sender);
        
        // claiming the NFT adds the new owner to the income distribution agreement subscribers 
        sf.host.callAgreement(sf.agreements.ida.address, sf.agreements.ida.contract.methods.updateSubscription
            (daix.address, sourceTokenId, msg.sender, newShares, "0x").encodeABI(), { from: address(this) })
            
        // claiming the NFT approves the subscription
        sf.host.callAgreement(sf.agreements.ida.address, sf.agreements.ida.contract.methods.approveSubscription
            (daix.address, address(this), sourceTokenId, "0x").encodeABI(), { from: msg.sender })
            
        // claiming the NFT distributes the auction's accumulated funds to the revenue share owners
        sf.host.callAgreement(sf.agreements.ida.address, sf.agreements.ida.contract.methods.updateIndex
           (daix.address, sourceTokenId, balanceOf(address(this)), "0x").encodeABI(), { from: address(this) })
        
        // claiming an NFT automatically mints a childNFT and starts a new auction
        uint childNFT = _mintChildNFT(tokenId);
        
        // claiming an NFT 
        _nextAuction(childNFT);
        
        emit auctionWon(tokenId, msg.sender);
        emit newAuction(childNFT, now);
        return true;
    }
  
    function _mintChildNFT(uint tokenId) private returns (uint) {
        uint childTokenId = tokenId + 1000000001; 
        childNFTs.push(childTokenId);
        NFTContract._safeMint(msg.sender, childTokenId);
        return childTokenId;
    }
    
    function _updateRevShares(address _newOwner) private returns (uint) {
        revShareRecipients.push(_newOwner);
        uint position = ownerRevShares.length - 1;
        uint newShares = ownerRevShares[position]*0.9;
        ownerRevShares.push(newShares);
        return newShares;
 }
