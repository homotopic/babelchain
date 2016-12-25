/* global require describe it ethers beforeEach */

const { expect, assert } = require('chai')
const { waffle } = require("@nomiclabs/buidler")
const { deployContract, MockProvider } = waffle

describe('AutoBond', () => {

  let curve
  let AutoBond
  let autoBond
  let reserveToken
  let owner
  let alice
  let bob
  let carol
  let treasury
  let autoBondAsAlice
  let autoBondAsBob
  let autoBondAsCarol
  let autoBondAsTreasury

  const networkFeeBasisPoints = 200

  beforeEach(async () => {
    [owner, treasury, alice, bob, carol] = await ethers.getSigners()

    const SimpleLinearCurve = await ethers.getContractFactory('SimpleLinearCurve')
    AutoBond = await ethers.getContractFactory('AutoBond')
    const ERC20 = await ethers.getContractFactory('ERC20')

    reserveToken = await ERC20.deploy('reserveToken', 'RT')
    curve = await SimpleLinearCurve.deploy()
    await reserveToken.deployed()
    await curve.deployed()
    autoBond = await AutoBond.deploy(
      networkFeeBasisPoints,
      reserveToken.address,
      curve.address,
      treasury.getAddress(),
    )
    await autoBond.deployed()

    autoBondAsTreasury = autoBond.connect(treasury)
    autoBondAsAlice = autoBond.connect(alice)
    autoBondAsBob = autoBond.connect(bob)
    autoBondAsCarol = autoBond.connect(carol)
  })

  //  Deploying

  it('handles good constructor parameters correctly', async () => {
    const cases = [
      // param name, expected value, actual value
      ['owner', await owner.getAddress(), await autoBond.owner()],
      ['network fee', networkFeeBasisPoints, await autoBond.networkFeeBasisPoints()],
      ['curve', curve.address, await autoBond.curve()],
      ['treasury', await treasury.getAddress(), await autoBond.treasury()],
    ]
    cases.forEach(([param, expected, actual]) => {
      assert.equal(expected, actual, `expected ${expected} ${param}, got ${actual}`)
    })
  })

  it("Won't deploy with bad constructor parameters", async () => {
    // should revert when zero address is passed for the resurve token
    await expect(AutoBond.deploy(
      0,
      ethers.constants.AddressZero, // <-- reserve token
      curve.address,
      await treasury.getAddress(),
    )).to.be.revertedWith("Reserve Token ERC20 address required")

    // should revert when zero address is passed for the curve address
    await expect(AutoBond.deploy(
      0,
      reserveToken.address,
      ethers.constants.AddressZero, // <-- curve address
      await treasury.getAddress(),
    )).to.be.revertedWith("Curve address required")

    // should revert when zero address is passed for the treasury address
    await expect(AutoBond.deploy(
      0,
      reserveToken.address,
      curve.address,
      ethers.constants.AddressZero, // <-- treasury address
    )).to.be.revertedWith("Treasury address required")
  })

  // Administration

  // check that it reverts if the wrong current fee is sent when
  // trying to change the fee

  it("Only lets the owner change admin properties", async () => {
    await expect(autoBondAsAlice.setNetworkFeeBasisPoints(
      await autoBond.networkFeeBasisPoints(),
      5040,
    )).to.be.revertedWith("Ownable: caller is not the owner")

    await expect(autoBond.setNetworkFeeBasisPoints(
      await autoBond.networkFeeBasisPoints(),
      5040,
    )).not.to.be.reverted
  })

  it("Owner can stop the experiment", async () => {
    // what happens when it's turned off, when the experiment is over?
    // Turn off every function except the getters, sell, and withdraw

    // set up
    // A few people make a few bonds and a few people buy from each
    // someone other than the owner calls stop in there somewhere, it
    // should revert and buying and selling should keep going

    // owner calls stop

    // check no one can do anything except call getters, sell, and
    // withdraw. when everything is withdrawn there is a zero balance
    // in all bonds (allowing for an epsilon of rounding error)

    assert(false, "Not Implemented")
  })

  // Submiting

  it("Lets Alice make and administer a new bond", async () => {
    const bondId = ethers.utils.formatBytes32String("testAliceBondId0")
    const metadata = ethers.utils.formatBytes32String("testAliceBondMetaData0")
    const benefactor = await alice.getAddress()
    const benefactorBasisPoints = ethers.BigNumber.from("179")
    const purchasePrice = ethers.constants.WeiPerEther.mul("10") // 10 bucks

    await expect(
      autoBondAsAlice.createBond(
        bondId,
        benefactor,
        benefactorBasisPoints,
        purchasePrice,
        metadata
      )
    ).to.emit(autoBond, "NewBond").withArgs(
      bondId,
      benefactor,
      benefactorBasisPoints,
      purchasePrice,
      metadata
    )

    // Alice can set the purchase price on their bond
    const newPurchasePrice = ethers.constants.WeiPerEther.mul(12) // 12 bucks
    await expect(
      autoBondAsAlice.setPurchasePrice(bondId, purchasePrice, newPurchasePrice)
    ).to.emit(autoBond, "PurchasePriceSet").withArgs(
      purchasePrice, newPurchasePrice
    )

    // Alice needs to assign the correct current purchase price to change it
    const anotherPurchasePrice = ethers.constants.WeiPerEther.mul(5)
    await expect(
      autoBondAsAlice.setPurchasePrice(bondId, purchasePrice, anotherPurchasePrice)
    ).to.be.revertedWith("AutoBond: currentPrice missmatch")

    // Bob cannot set the purchase price on Alice's bond
    const bobsPurchasePrice = ethers.constants.WeiPerEther
    await expect(
      autoBondAsBob.setPurchasePrice(bondId, newPurchasePrice, bobsPurchasePrice)
    ).to.be.revertedWith("AutoBond: only the benefactor can set a purchase price")

    // The bond was set up correctly
    const alicesBond = await autoBondAsCarol.bonds(bondId)
    const cases = [
      ["supply", "0", alicesBond.supply.toString()],
      ["benefactor", await alice.getAddress(), alicesBond.benefactor],
      ["benefactorBasisPoints", benefactorBasisPoints.toString(), alicesBond.benefactorBasisPoints.toString()],
      ["purchasePrice", newPurchasePrice.toString(), alicesBond.purchasePrice.toString()],
      ["balances", {}, alicesBond.balances],
    ]

    cases.forEach(([property, expected, actual]) => {
      console.log(property, expected, actual)
      assert(expected === actual,
             `expected Bond.${property} to be ${expected} but got ${actual}`)
    })
  })

  it("Never lets basis points represent more than 100%", async () => {
    assert(false, "Not Implemented")
  })

  it("Gives Alice rights of first purchase", async () => {
    assert(false, "Not Implemented")
  })

  it("Only lets Alice change the purchase price", async () => {
    assert(false, "Not Implemented")
  })

  it("Lets only Alice change the benefactor", async () => {
    assert(false, "Not Implemented")
  })

  // Puchasing
  it("Lets Bob buy the good backed by the bond", async () => {
    assert(false, "Not Implemented")
  })

  it("Lets benefactor and the owner withdraw their surplus share", async () => {
    assert(false, "Not Implemented")
  })

  it("Lets Bob 'refinance' the good", async () => {
    // maybe post MVP?
    assert(false, "Not Implemented")
  })

  // Curating
  it("Lets Carol curate/invest in the bond", async () => {
    assert(false, "Not Implemented")
  })
})
