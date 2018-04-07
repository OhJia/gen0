Contract inheritance
* KittyAccessControl --> KokoroAccessControl
* KittyBase is KittyAccessControl --> KokoroFactory is KokoroAccessControl
* KittyOwnership is KittyBase, ERC721 --> KokoroOwnership is KokoroFactory
* KittyBreeding is KittyOwnership --> KokoroMating is KokoroOwnership
* KittyAuction is KittyBreeding --> KokoroAuction is KokoroMating
* KittyMinting is KittyAuction
* KittyCore is KittyMinting

Auctions
* ClockAuctionBase
* ClockAuction is ClockAuctionBase
* SaleClockAuction is ClockAuction
* SiringClockAuction is ClockAuction