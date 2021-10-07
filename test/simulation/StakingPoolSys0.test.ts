import { expect } from 'chai'
import { ethers } from 'hardhat'
import { BigNumber, ContractFactory } from 'ethers'
import { MAX_UINT256 } from '../../common/constants'
import { bn } from '../../common/numbers'
import { advanceTime } from '../utils/time'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { ERC20Mock } from '../../typechain/ERC20Mock'
import { StakingPoolSys0 } from '../../typechain/StakingPoolSys0'

describe('StakingPoolSys0 contract', () => {
  let owner: SignerWithAddress
  let addr1: SignerWithAddress
  let addr2: SignerWithAddress
  let other: SignerWithAddress

  let ERC20: ContractFactory
  let rToken: ERC20Mock
  let rsr: ERC20Mock
  let stkPool: StakingPoolSys0
  let initialBal: BigNumber

  beforeEach(async () => {
    ;[owner, addr1, addr2, other] = await ethers.getSigners()

    // Deploy RToken and RSR Token
    ERC20 = await ethers.getContractFactory('ERC20Mock')
    rToken = <ERC20Mock>await ERC20.deploy('RToken', 'RTKN')
    rsr = <ERC20Mock>await ERC20.deploy('Reserve Rights', 'RSR')

    // Mint initial amounts
    initialBal = bn(100e18)
    rsr.connect(owner).mint(addr1.address, initialBal)
    rsr.connect(owner).mint(addr2.address, initialBal)
    // Deploy StakingPool_Sys0
    const StakingPool = await ethers.getContractFactory('StakingPoolSys0')
    stkPool = <StakingPoolSys0>await StakingPool.connect(owner).deploy(rToken.address, rsr.address, 0)
    //await rToken.connect(owner).updateConfig({ ...config, insurancePool: iPool.address })
  })

  describe('Deployment', () => {
    it('Deployment should setup initial addresses and values correctly', async () => {
      expect(await stkPool.rToken()).to.equal(rToken.address)
      expect(await stkPool.rsr()).to.equal(rsr.address)
      expect(await rsr.balanceOf(stkPool.address)).to.equal(0)
      expect(await rsr.allowance(stkPool.address, rToken.address)).to.equal(MAX_UINT256)
      expect(await stkPool.balanceOf(owner.address)).to.equal(0)
      expect(await stkPool.balanceOf(addr1.address)).to.equal(0)
      expect(await stkPool.balanceOf(addr2.address)).to.equal(0)
    })
  })

  describe('Deposits/Staking', () => {
    it('Should allow to stake/deposit in RSR', async () => {
      // Perform stake
      const amount: BigNumber = bn(1e18)

      // Approve transfer and stake
      await rsr.connect(addr1).approve(stkPool.address, amount)
      await stkPool.connect(addr1).stake(amount)

      // Check balances and stakes
      expect(await rsr.balanceOf(stkPool.address)).to.equal(amount)
      expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
      expect(await rsr.balanceOf(addr1.address)).to.equal(initialBal.sub(amount))
      expect(await stkPool.balanceOf(addr1.address)).to.equal(amount)
    })

    it('Should not allow to stake amount = 0', async () => {
      // Perform stake
      const amount: BigNumber = bn(1e18)
      const zero: BigNumber = bn(0)

      // Approve transfer and stake
      await rsr.connect(addr1).approve(stkPool.address, amount)
      await expect(stkPool.connect(addr1).stake(zero)).to.be.revertedWith('Cannot stake zero')

      // Check deposit not registered
      expect(await rsr.balanceOf(stkPool.address)).to.equal(0)
      expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
      expect(await rsr.balanceOf(addr1.address)).to.equal(initialBal)
      expect(await stkPool.balanceOf(addr1.address)).to.equal(0)
    })

    it('Should allow multiple stakes/deposits in RSR', async () => {
      // Perform stake
      const amount1: BigNumber = bn(1e18)
      const amount2: BigNumber = bn(2e18)
      const amount3: BigNumber = bn(3e18)

      // Approve transfer and stake twice
      await rsr.connect(addr1).approve(stkPool.address, amount1.add(amount2))
      await stkPool.connect(addr1).stake(amount1)
      await stkPool.connect(addr1).stake(amount2)

      // New stake from different account
      await rsr.connect(addr2).approve(stkPool.address, amount3)
      await stkPool.connect(addr2).stake(amount3)

      // Check balances and stakes
      expect(await rsr.balanceOf(stkPool.address)).to.equal(amount1.add(amount2).add(amount3))
      expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
      expect(await rsr.balanceOf(addr1.address)).to.equal(initialBal.sub(amount1).sub(amount2))
      expect(await stkPool.balanceOf(addr1.address)).to.equal(amount1.add(amount2))
      expect(await rsr.balanceOf(addr2.address)).to.equal(initialBal.sub(amount3))
      expect(await stkPool.balanceOf(addr2.address)).to.equal(amount3)
    })
  })

  describe('Withdrawals/Unstaking', () => {
    it('Should create Pending withdrawal when unstaking', async () => {
      const amount: BigNumber = bn(1e18)

      // Stake
      await rsr.connect(addr1).approve(stkPool.address, amount)
      await stkPool.connect(addr1).stake(amount)

      // Unstake
      await stkPool.connect(addr1).unstake(amount)

      // Check withdrawal properly registered
      const [unstakeAcc, unstakeAmt] = await stkPool.withdrawals(0)
      expect(unstakeAcc).to.equal(addr1.address)
      expect(unstakeAmt).to.equal(amount)

      // Check balances and stakes (unchanged)
      expect(await rsr.balanceOf(stkPool.address)).to.equal(amount)
      expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
      expect(await rsr.balanceOf(addr1.address)).to.equal(initialBal.sub(amount))
      expect(await stkPool.balanceOf(addr1.address)).to.equal(amount)
    })

    it('Should not allow to unstake amount = 0', async () => {
      const zero: BigNumber = bn(0)

      // Unstake
      await expect(stkPool.connect(addr1).unstake(zero)).to.be.revertedWith('Cannot withdraw zero')
    })

    it('Should not allow to unstake if not enough balance', async () => {
      const amount: BigNumber = bn(1e18)

      // Unstake with no stakes/balance
      await expect(stkPool.connect(addr1).unstake(amount)).to.be.revertedWith('Not enough balance')
    })

    it('Should allow multiple unstakes/withdrawals in RSR', async () => {
      // Perform stake
      const amount1: BigNumber = bn(1e18)
      const amount2: BigNumber = bn(2e18)
      const amount3: BigNumber = bn(3e18)

      // Approve transfers
      await rsr.connect(addr1).approve(stkPool.address, amount1.add(amount2))
      await rsr.connect(addr2).approve(stkPool.address, amount3)

      // Stake
      await stkPool.connect(addr1).stake(amount1)
      await stkPool.connect(addr1).stake(amount2)
      await stkPool.connect(addr2).stake(amount3)

      // Unstake - Create withdrawal
      await stkPool.connect(addr1).unstake(amount1)
      let [unstakeAcc, unstakeAmt] = await stkPool.withdrawals(0)
      expect(unstakeAcc).to.equal(addr1.address)
      expect(unstakeAmt).to.equal(amount1)

      // Unstake again
      await stkPool.connect(addr1).unstake(amount2)
      ;[unstakeAcc, unstakeAmt] = await stkPool.withdrawals(1)
      expect(unstakeAcc).to.equal(addr1.address)
      expect(unstakeAmt).to.equal(amount2)

      // Unstake again with different user (will process previous stake)
      await stkPool.connect(addr2).unstake(amount3)
      ;[unstakeAcc, unstakeAmt] = await stkPool.withdrawals(2)
      expect(unstakeAcc).to.equal(addr2.address)
      expect(unstakeAmt).to.equal(amount3)
    })

    context('With deposits and withdrawals', async () => {
      let amount1: BigNumber
      let amount2: BigNumber
      let amount3: BigNumber
      const stkWithdrawalDelay = 20000

      beforeEach(async () => {
        // Set stakingWithdrawalDelay
        await stkPool.setStakingWithdrawalDelay(stkWithdrawalDelay)

        // Perform stake
        amount1 = bn(1e18)
        amount2 = bn(2e18)
        amount3 = bn(3e18)

        // Approve transfers
        await rsr.connect(addr1).approve(stkPool.address, amount1)
        await rsr.connect(addr2).approve(stkPool.address, amount2.add(amount3))

        // Stake
        await stkPool.connect(addr1).stake(amount1)
        await stkPool.connect(addr2).stake(amount2)
        await stkPool.connect(addr2).stake(amount3)

        // Unstake - Create withdrawal
        await stkPool.connect(addr1).unstake(amount1)
      })

      it('Should not process withdrawals before stakingWithdrawalDelay', async () => {
        // Process unstakes
        await stkPool.processWithdrawals()

        // Nothing processed so far
        expect(await stkPool.withdrawalIndex()).to.equal(0)
        expect(await stkPool.totalStaked()).to.equal(amount1.add(amount2).add(amount3))
        expect(await rsr.balanceOf(addr1.address)).to.equal(initialBal.sub(amount1))
        expect(await stkPool.balanceOf(addr1.address)).to.equal(amount1)

        // Process unstakes after certain time (still before stakingWithdrawalDelay)
        await advanceTime(15000)

        await stkPool.processWithdrawals()

        // Nothing processed still
        expect(await stkPool.withdrawalIndex()).to.equal(0)
        expect(await stkPool.totalStaked()).to.equal(amount1.add(amount2).add(amount3))
        expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
        expect(await rsr.balanceOf(addr1.address)).to.equal(initialBal.sub(amount1))
        expect(await stkPool.balanceOf(addr1.address)).to.equal(amount1)
      })

      it('Should process withdrawals after stakingWithdrawalDelay', async () => {
        // Get current balance for user
        const prevAddr1Balance = await rsr.balanceOf(addr1.address)

        // Move forward past stakingWithdrawalDelay
        await advanceTime(stkWithdrawalDelay + 1)

        // Process unstakes
        await stkPool.processWithdrawals()

        // Withdrawal was processed
        expect(await stkPool.withdrawalIndex()).to.equal(1)
        expect(await stkPool.totalStaked()).to.equal(amount2.add(amount3))
        expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
        expect(await rsr.balanceOf(addr1.address)).to.equal(prevAddr1Balance.add(amount1))
        expect(await stkPool.balanceOf(addr1.address)).to.equal(0)
      })

      it('Should store weights and calculate balance correctly', async () => {
        // Get current balances for users
        const prevAddr1Balance = await rsr.balanceOf(addr1.address)
        const prevAddr2Balance = await rsr.balanceOf(addr2.address)

        // Create additional withdrawal - Will process previous one
        await stkPool.connect(addr2).unstake(amount2)

        // Move forward past stakingWithdrawalDelaylay
        await advanceTime(stkWithdrawalDelay + 1)

        // Process unstakes
        await stkPool.processWithdrawals()

        // Withdrawals were processed
        expect(await stkPool.withdrawalIndex()).to.equal(2)
        expect(await stkPool.totalStaked()).to.equal(amount3)
        expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
        expect(await rsr.balanceOf(addr1.address)).to.equal(prevAddr1Balance.add(amount1))
        expect(await stkPool.balanceOf(addr1.address)).to.equal(0)
        expect(await rsr.balanceOf(addr2.address)).to.equal(prevAddr2Balance.add(amount2))
        expect(await stkPool.balanceOf(addr2.address)).to.equal(amount3)

        // Create additional withdrawal
        await stkPool.connect(addr2).unstake(amount3)

        // Move forward past stakingWithdrawalDelay
        await advanceTime(stkWithdrawalDelay + 1)

        // Process unstakes
        await stkPool.processWithdrawals()

        // Withdrawals processed
        expect(await stkPool.withdrawalIndex()).to.equal(3)
        expect(await stkPool.totalStaked()).to.equal(0)
        expect(await rsr.balanceOf(stkPool.address)).to.equal(await stkPool.totalStaked())
        expect(await rsr.balanceOf(addr1.address)).to.equal(prevAddr1Balance.add(amount1))
        expect(await stkPool.balanceOf(addr1.address)).to.equal(0)
        expect(await rsr.balanceOf(addr2.address)).to.equal(prevAddr2Balance.add(amount2).add(amount3))
        expect(await stkPool.balanceOf(addr2.address)).to.equal(0)
      })
    })
  })
})
