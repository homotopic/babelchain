// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.6.0 <0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AutoBond is Ownable {
    using SafeMath for uint256;
    using SafeMath for uint16;

    /*
     *  State
     */

    // when the experiment is over some functionality will stop working
    bool public stopped = false;

    // basis points
    uint16 public networkFeeBasisPoints;

    // address where network fees are sents
    address public treasury;

    // accounts hold funds that may be withdrawn
    mapping(address => uint256) public accounts;

    // ERC20 token backing the bonds
    address public reserveToken;

    Curve public curve;

    struct Bond {
        // benefactor may claim the surplus for this bond
        address benefactor;
        // basis points taken out of every sale as surplus for the
        // benefactor
        uint16 benefactorBasisPoints;
        // purchasePrice is emitted in the purchase event so clients can
        // check whether how much a user needs to have for a calid
        // purchase
        uint256 purchasePrice;

        // let these default to 0
        uint256 supply;
        mapping(address => uint256) balances;
    }

    // mapping from definition ID to it's bond
    mapping(bytes32 => Bond) public bonds;

    modifier stoppable() {
        require(stopped != true, "The experiment is stopped");
        _;
    }

    /*
     *  Methods
     */

    constructor(
        uint16 _networkFeeBasisPoints,
        address _reserveToken,
        address _curve,
        address _treasury
    ) public {
        require(_networkFeeBasisPoints <= 10000, "AutoBond: Network fee greater than 100%");
        require(
            _reserveToken != address(0),
            "Reserve Token ERC20 address required"
        );
        require(_curve != address(0), "Curve address required");
        require(_treasury != address(0), "Treasury address required");
        networkFeeBasisPoints = _networkFeeBasisPoints;
        emit NetworkFeeBasisPointsChange(0, networkFeeBasisPoints);
        reserveToken = _reserveToken;
        curve = Curve(_curve);
        treasury = _treasury;
    }

    /*
     *  Admin
     */

    event ExperimentOver();

    function stop() public onlyOwner {
        require(stopped == false, "Already stopped");
        stopped = true;
        emit ExperimentOver();
    }

    // GlobalFeeBasisPointsChange is emitted when the fee rate changes
    event NetworkFeeBasisPointsChange(
        uint16 fromBasisPoints,
        uint16 toBasisPoints
    );

    // setNetworkFeeBasisPoints allows the owner to change the network fee rate
    function setNetworkFeeBasisPoints(
        uint16 fromBasisPoints,
        uint16 toBasisPoints
    ) public onlyOwner stoppable {
        require(
            networkFeeBasisPoints == fromBasisPoints,
            "fromBasisPoints mismatch"
        );
        require(toBasisPoints <= 10000, "AutoBond: toBasisPoints greater than 100%");
        networkFeeBasisPoints = toBasisPoints;
        emit NetworkFeeBasisPointsChange(fromBasisPoints, toBasisPoints);
    }

    // withdraw transfers all owed fees to the network owner and all
    // owed royalties to msg.sender
    function withdraw(address benefactor) public {
        require(benefactor != address(0), "benefactor address required");
        require(accounts[benefactor] > 0, "Nothing to withdraw");

        // calculate the network fee
        uint256 (networkFee, benefactorTotal) = _calculateFeeSplit(networkFeeBasisPoints, accounts[benefactor]);

        // transfer the account total minus the network fee to the benefactor
        require(IERC20(reserveToken).transfer(benefactorTotal));

        // transfer the fee to the treasury
        require(IERC20(reserveToken).transfer(treasury, networkFee));
    }

    // NewBond is emitted when a new bond is created. The submitter may
    // add arbitrary metadata for clients to build catalogs from
    event NewBond(bytes32 bondId,
                  address benefactor,
                  uint16 benefactorBasisPoints,
                  uint256 purchasePrice,
                  string metadata);

    function createBond(
        bytes32 bondId,
        address benefactor,
        uint16 benefactorBasisPoints,
        uint256 purchasePrice,
        string memory metadata
    ) public stoppable {
        require(benefactor != address(0), "AutoBond: Benefactor address required");
        require(benefactorBasisPoints <= 10000, "AutoBond: benefactorBasisPoints greater than 100%");

        Bond storage newBond = bonds[bondId];
        require(newBond.benefactor == address(0), "AutoBond: Bond already exists");
        newBond.benefactor = benefactor;
        newBond.benefactorBasisPoints = benefactorBasisPoints;
        newBond.purchasePrice = purchasePrice;

        emit NewBond(bondId, benefactor, benefactorBasisPoints, purchasePrice, metadata);
    }

    event PurchasePriceSet(uint256 currentPrice, uint256 newPrice);

    function setPurchasePrice(bytes32 bondId,
                              uint256 currentPrice,
                              uint256 newPrice) public stoppable {
        require(bonds[bondId].benefactor == msg.sender,
                "AutoBond: only the benefactor can set a purchase price");
        require(bonds[bondId].purchasePrice == currentPrice,
                "AutoBond: currentPrice missmatch");
        bonds[bondId].purchasePrice = newPrice;
        emit PurchasePriceSet(currentPrice, newPrice);
    }

    // Purchase is emitted on all bond purchases, and includes enough
    // informatino for clients to track whether someone owns the
    // license according to the purchasePrice at the time of purchase
    event Purchase(
        bytes32 bondId,
        address purchaser,
        uint256 amountPurchased,
        uint256 amountPaid,
        uint256 purchasePrice
    );

    function _calculateFeeSplit(
                             uint16 basisPoints,
                             uint256 total
                             ) internal returns (uint256, uint256) {
        uint256 memory fee;
        uint256 memory remainder;
        fee = total.mul(basisPoints).div(1000);
        remainder = total - fee;
        return (fee, remainder);
    }

    // mint and buy some amount of some bond
    function buy(
        bytes32 bondId,
        uint256 amount,
        uint256 maxPrice
    ) public stoppable {
        // get the total price for the amount
        Bond memory bond = bonds[bondId];
        uint256 totalPrice = curve.price(bond.supply, amount);
        require(totalPrice <= maxPrice, "price higher than maxPrice");
        // Charge the sender totalPrice
        require(
            IERC20(reserveToken).transferFrom(
                msg.sender,
                address(this),
                totalPrice
            )
        );

        // add benefactor fee to the benefactor's account
        uint256 (benefactorFee, _) = _calculateFeeSplit(bond.benefactorBasisPoints, amount);
        accounts[bond.benefactor] = accounts[bond.benefactor].add(benefactorSurplus);

        emit Purchase(bondId, msg.sender, amount, totalPrice, bond.purchasePrice);
    }

    function sell(
        bytes32 bondId,
        uint256 amount,
        uint256 minValue
    ) public {
        // sell curve = buy curve scaled down by bond.benefactorBasisPoints
        Bond memory bond = bonds[bondId];
        require(bond.supply >= amount, "not enough supply");
        require(false, "Seller doesn't own enough to sell");
        uint256 subtotalValue = curve.price(
            bond.supply.sub(amount),
            bond.supply
        );
        uint256 (benefactorFee, totalValue) = _calculateFeeSplit(bond.benefactorBasisPoints, subtotalValue);
        require(totalValue >= minValue, "value lower than minValue");
        bond.supply = bond.supply.sub(amount);
        require(IERC20(reserveToken).transfer(msg.sender, totalValue));
        accounts[benefactor] = accounts[benefactor].add(benefactorFee);

        // TODO emit Purchase event for what was left
    }
}

interface Curve {
    function price(uint256 supply, uint256 units)
        external
        view
        returns (uint256);
}

contract SimpleLinearCurve is Curve {
    using SafeMath for uint256;

    constructor() public {}

    function price(uint256 supply, uint256 units)
        public
        override
        view
        returns (uint256)
    {
        // sum of the series from supply + 1 to new supply or (supply + units)
        // average of the first term and the last term timen the number of terms
        //                supply + 1         supply + units      units

        uint256 a1 = supply.add(1); // the first newly minted token
        uint256 an = supply.add(units); // the last newly minted token
        uint256 n = units; // number of tokens in the series

        // the forumula is n((a1 + an)/2)
        // but deviding integers by 2 introduces errors that are then multiplied
        // factor the formula to devide by 2 last

        // ((a1 * n) + (a2 * n)) / 2

        return a1.mul(n).add(an.mul(n)).div(2);
    }
}
