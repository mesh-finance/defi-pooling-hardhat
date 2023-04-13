

import { FakeContract, smock } from "@defi-wonderland/smock";

import { BigNumber, parseFixed } from "@ethersproject/bignumber";
import chai, { expect } from "chai";
// import { ethers } from "ethers";
import hre from "hardhat";
// import {
//   assertPublicMutableMethods,
//   simpleDeploy,
//   testAuth,
// } from "@makerdao/hardhat-utils";
import { AbiCoder } from "ethers/lib/utils";
import { eth, split } from "../utils";
const { ethers } = require("hardhat");
chai.use(smock.matchers);


const MAX_UINT256 = hre.ethers.constants.MaxUint256;

const DISTRIBUTE_SHARES_SELECTOR = "3520401815844567356085155807608885419463728554843487745";
const DISTRIBUTE_UNDERLYING_SELECTOR = "3520401815844567356085155807608885419463728554843487745";
// stargate deposit selector
const DEPOSIT_SELECTOR = "1285101517810983806491589552491143496277809242732141897358598292095611420389";

const MESSAGE_WITHDRAWAL_REQUEST = 1;
const MESSAGE_DEPOSIT_REQUEST = 2;
const TRANSFER_FROM_STARKNET = 0;

function toSplitUint(value: any) {
    const bits = value.toBigInt().toString(16).padStart(64, "0");
    return [BigInt(`0x${bits.slice(32)}`), BigInt(`0x${bits.slice(0, 32)}`)];
}

describe("l1:L1DefiPooling", function () {
  it("initializes properly", async () => {
    const { admin, usdc, starkNetFake, l1Bridge,l1DefiPooling, l2DefiPoolingAddress } =
      await setupTest();

    expect(await l1DefiPooling.starknetCore()).to.be.eq(starkNetFake.address);
    expect(await l1DefiPooling.underlying()).to.be.eq(usdc.address);
    expect(await l1DefiPooling.starknetERC20Bridge()).to.be.eq(l1Bridge.address);
    expect(await l1DefiPooling.l2Contract()).to.be.eq(l2DefiPoolingAddress);

    expect(await usdc.balanceOf(admin.address)).to.be.eq(eth("1000000"));
  });
});
  describe("depositAndDestributeSharesonL2", function () {
    it("claims underlying from skartnetERC20Bridge -> deposit to yearn -> and sends a message to l2 to distribute shares", async () => {
      const {
        admin,
        account1,
        usdc,
        starkNetFake,
        l1Bridge,
        l2BridgeAddress,
        l1DefiPooling,
        l2DefiPoolingAddress,
        vault
      } = await setupTest();

      const depositAmount = eth("333");
      const depositId = 0;
      

      // funding the l1 bridge to claim from it.
      await usdc.connect(admin).transfer(l1Bridge.address, depositAmount);

      const expectedShares = await vault.previewDeposit(depositAmount)
      // await l1DefiPooling.connect(admin).depositAndDisbtributeSharesOnL2(depositId, depositAmount)
      await expect(l1DefiPooling.connect(admin).depositAndDisbtributeSharesOnL2(depositId, depositAmount))
        .to.emit(l1DefiPooling, "Deposited")
        .withArgs(depositId, depositAmount,expectedShares);


        expect(starkNetFake.consumeMessageFromL2).to.have.been.calledTwice;
        expect(starkNetFake.consumeMessageFromL2).to.have.been.calledWith(
          l2DefiPoolingAddress,
          [MESSAGE_DEPOSIT_REQUEST, depositId, ...split(depositAmount)]
        );

        expect(starkNetFake.consumeMessageFromL2).to.have.been.calledWith(
          l2BridgeAddress,
          [TRANSFER_FROM_STARKNET, l1DefiPooling.address, ...split(depositAmount)]
        );

      expect(await usdc.balanceOf(l1Bridge.address)).to.be.eq(0);
      expect(await usdc.balanceOf(l1DefiPooling.address)).to.be.eq(0);

      expect(starkNetFake.sendMessageToL2).to.have.been.calledOnce;
      // console.log("agres",sharesReceieved)
      // console.log("shares",expectedShares)
      expect(starkNetFake.sendMessageToL2).to.have.been.calledWith(
        l2DefiPoolingAddress,
        DISTRIBUTE_SHARES_SELECTOR,
        [depositId, ...split(expectedShares)]
      );

      //TODO: verify sharesReceieved is equal to IYearnV2Vault(yearnVault).balanceOf(l1DefiPooling.address)
      expect(await vault.balanceOf(l1DefiPooling.address)).to.be.eq(expectedShares);

    });
    it("reverts when deposit Amount is not correct", async () => {
      const {
        admin,
        account1,
        usdc,
        starkNetFake,
        l1Bridge,
        l2BridgeAddress,
        l1DefiPooling,
        l2DefiPoolingAddress
      } = await setupTest();

      const actualDepositAmount = eth("333");
      const wrongDepositAmount = eth("300");

      const depositId = 0;

      // funding the l1 bridge to claim from it.
      await usdc.connect(admin).transfer(l1Bridge.address, actualDepositAmount);

      starkNetFake.consumeMessageFromL2
        .whenCalledWith(l2DefiPoolingAddress, [
          MESSAGE_DEPOSIT_REQUEST,
          depositId,
          ...split(wrongDepositAmount),
        ])
        .reverts();

      await expect(
        l1DefiPooling.connect(admin).depositAndDisbtributeSharesOnL2(depositId, wrongDepositAmount)
      ).to.be.reverted;

      expect(starkNetFake.consumeMessageFromL2).to.have.been.calledWith(
        l2DefiPoolingAddress,
        [MESSAGE_DEPOSIT_REQUEST, depositId, ...split(wrongDepositAmount)]
      );
  });
});

describe("withdrawAndDistributeUnderlyingOnL2", function () {
  it("withdraw from yearn -> bridge usdc -> distribute on L2", async () => {
    const {
      admin,
      account1,
      usdc,
      starkNetFake,
      l1Bridge,
      l2BridgeAddress,
      l1DefiPooling,
      l2DefiPoolingAddress,
      vault
    } = await setupTest();

    const depositAmount = eth("333");
    const depositId = 0;
    const withdrawId = 0;
    
    // funding the l1 bridge to claim from it.
    await usdc.connect(admin).transfer(l1Bridge.address, depositAmount);

    await l1DefiPooling.connect(admin).depositAndDisbtributeSharesOnL2(depositId, depositAmount)


    const sharesReceieved = await vault.balanceOf(l1DefiPooling.address)
    const sharesToWithdraw = BigNumber.from(sharesReceieved).div(2)
    // const sharesToWithdraw = sharesReceieved

    const expectedAmountReceived = await vault.previewRedeem(sharesToWithdraw)

    await expect(
      l1DefiPooling.connect(admin).withdrawAndBridgeBack(withdrawId, sharesToWithdraw)
    )
      .to.emit(l1DefiPooling, "Withdrawed")
      .withArgs(withdrawId, sharesToWithdraw,expectedAmountReceived);

    // expect(await dai.balanceOf(l1Alice.address)).to.be.eq(withdrawalAmount);
    // expect(await dai.balanceOf(l1Bridge.address)).to.be.eq(0);
    // expect(await dai.balanceOf(escrow.address)).to.be.eq(0);

    // twice in deposit and once in withdraw
    expect(starkNetFake.consumeMessageFromL2).to.have.been.calledThrice;
    expect(starkNetFake.consumeMessageFromL2).to.have.been.calledWith(
      l2DefiPoolingAddress,
      [MESSAGE_WITHDRAWAL_REQUEST, withdrawId, ...split(sharesToWithdraw)]
    );

    expect(await vault.balanceOf(l1DefiPooling.address)).to.be.eq(BigNumber.from(sharesReceieved).sub(sharesToWithdraw));
    expect(await usdc.balanceOf(l1Bridge.address)).to.be.eq(expectedAmountReceived);

    // once in deposit and once in withdraw
    expect(starkNetFake.sendMessageToL2).to.have.been.calledTwice;
      expect(starkNetFake.sendMessageToL2).to.have.been.calledWith(
        l2BridgeAddress,
        DEPOSIT_SELECTOR,
        [l2DefiPoolingAddress, ...split(expectedAmountReceived)]
      );
    
      await expect(
        l1DefiPooling.connect(admin).distributeUnderlyingOnL2(withdrawId)
      )
        .to.emit(l1DefiPooling, "DistributedOnL2")
        .withArgs(withdrawId, expectedAmountReceived);

      expect(starkNetFake.sendMessageToL2).to.have.been.calledThrice;
      expect(starkNetFake.sendMessageToL2).to.have.been.calledWith(
        l2DefiPoolingAddress,
        DISTRIBUTE_UNDERLYING_SELECTOR,
        [withdrawId, ...split(expectedAmountReceived)]
      );
  });
});

async function setupTest() {
    const [admin, account1, account2] = await hre.ethers.getSigners();
  
    // let myContractFake: FakeContract<IStarknetMessaging>;
    const starkNetFake = await smock.fake(
      "StarknetMessaging"
    );
  
    // const Usdc = await simpleDeploy("USDC", []);
    const Usdc = await ethers.getContractFactory('USDC')
    const usdc = await Usdc.deploy();

    // const vault = await simpleDeploy("DummyVault", [usdc.address]);
    const Vault = await ethers.getContractFactory('DummyVault')
    const vault = await Vault.deploy(usdc.address);
    
    const L2_USDC_BRIDGE_ADDRESS = 31415;    // copied from makerDAO repo, assuming they are just dummy values.(not sure)
    const L2_USDC_ADDRESS = 27182;
    const L2_DEFI_POOLING_ADDRESS = 123756;
  
    // const l1Bridge = await simpleDeploy("StarknetERC20Bridge", [
    // ]);

    const L1Bridge = await ethers.getContractFactory('StarknetERC20Bridge')
    const l1Bridge = await L1Bridge.deploy();

    const abiCoder = ethers.utils.defaultAbiCoder;
    const initializeParameter = abiCoder.encode(["address", "address"],[usdc.address,starkNetFake.address])
    // await l1Bridge.connect(admin).initialize(initializeParameter)
    await l1Bridge.connect(admin).setL2TokenBridge(L2_USDC_BRIDGE_ADDRESS)
    await l1Bridge.connect(admin).setMaxTotalBalance("10000000000000000000000000")
    await l1Bridge.connect(admin).setMaxDeposit("10000000000000000000000000")
    // let messaging = await l1Bridge.messagingContract()
    // let bridgedToken = await l1Bridge.bridgedToken()
    let l2TokenBridge = await l1Bridge.l2TokenBridge()
    await l1Bridge.messagingContract(starkNetFake.address)
    await l1Bridge.bridgedToken(usdc.address)
    // console.log(messaging)
    // console.log(l2TokenBridge)
    // console.log(starkNetFake.address)
    // console.log(usdc.address)

    
    const YearnV2Strategy = await ethers.getContractFactory('YearnV2Strategy')
    const l1DefiPooling = await YearnV2Strategy.deploy(usdc.address,
      vault.address,
      starkNetFake.address,
      L2_DEFI_POOLING_ADDRESS,
      l1Bridge.address);
  
    return {
      admin: admin as any,
      account1: account1 as any,
      account2: account2 as any,
      usdc: usdc as any,
      starkNetFake: starkNetFake as any,
      l1Bridge: l1Bridge as any,
      vault: vault as any,
      l1DefiPooling: l1DefiPooling as any,
      l2DefiPoolingAddress: L2_DEFI_POOLING_ADDRESS,
      l2BridgeAddress: L2_USDC_BRIDGE_ADDRESS,
      l2UsdcAddress: L2_USDC_ADDRESS,
    };
  }


