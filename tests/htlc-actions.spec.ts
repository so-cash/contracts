import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanEvent,
  cleanStruct,
  ganacheProvider,
  getLogs,
  map,
  receipientInfo,
  traceEventLog,
} from "./shared";
import { prepareContracts } from "./so-cash-prepare";
import { mineBlock, initWeb3Time } from "./shared/dates";
import { createAccount, createHTLCData } from "./shared";

describe("Test SoCash HTLC Functions", async function () {
  this.timeout(10000);
  const web3 = new Web3(ganacheProvider() as any);
  initWeb3Time(web3);
  let g: Awaited<ReturnType<typeof prepareContracts>> = {} as any;

  this.beforeEach(async () => {
    g = await prepareContracts(web3);
  });
  this.afterEach(() => {
    if (g.BankSubs) g.BankSubs.removeAllListeners();
    if (g.AccountSubs) g.AccountSubs.removeAllListeners();
  });

  it("Basic usage of htlc with a debit", async () => {
    //  Nostro of bank1 is funded and Bank1 wants to retrieve the funds

    // credit nostro bank 1
    await g.bank2.credit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      500_000,
      "Nostro funding",
    );
    // allow bank1 to operate its nostro
    await g.nostroBank1.whitelist(g.bo2User.send(), await g.bo1User.account());

    // Bank1 create secrets and all necessary elements
    const htlc1 = await createHTLCData();
    console.log("htlcData", htlc1);
    await g.nostroBank1.lockFunds(
      g.bo1User.send(),
      receipientInfo(g.nostroBank1.deployedAt),
      300_000,
      htlc1.timeout,
      htlc1.hash,
      htlc1.cancelHash,
      JSON.stringify({ tradeId: htlc1.tradeId, networkID: "POCR" }),
    );
    const logs = await getLogs(
      g.nostroBank1.events.HTLCPaymentCreated(g.bo1User.get(), {
        hashlockPaid: htlc1.hash,
      }),
    );
    expect(logs.length).to.equal(1);
    htlc1.id = logs[0].returnValues.id;
    console.log("htlcId", htlc1.id);
    // check the the funds are locked
    let balanceLocked = Number.parseInt(
      await g.nostroBank1.lockedBalance(g.bo1User.call()),
    );
    expect(balanceLocked).to.equal(300_000);

    // Bank2 has received the htlc id via the event and can make the payment
    const ev = cleanEvent(logs[0]).returnValues;
    console.log("htlc event", ev);

    const htlc2 = cleanStruct(
      await g.nostroBank1.getHTLCPayment(g.bo2User.call(), ev.id),
    );
    htlc2.id = ev.id;
    // making a successful payment in DL3S or other scheme reveals the secret
    htlc2.secret = htlc1.secret;
    console.log("htlc2", htlc2);
    // Bank2 can now claim the funds to cover its payment. It transfer the funds to the same account to unlock the funds
    await g.nostroBank1.transferLockedFunds(
      g.bo2User.send(),
      htlc2.id,
      receipientInfo(g.nostroBank1.deployedAt),
      htlc2.secret,
      "Redemption",
    );
    // And the funds are now unlocked
    balanceLocked = Number.parseInt(
      await g.bank2.lockedBalanceOf(g.bo2User.call(), g.nostroBank1.deployedAt),
    );
    expect(balanceLocked).to.equal(0);
    // check the event log
    const logs2 = await getLogs(
      g.nostroBank1.events.HTLCPaymentRemoved(g.bo2User.get(), {
        id: htlc2.id,
      }),
    );
    expect(logs2.length).to.equal(1);
    expect(logs2[0].returnValues.cancelled).to.be.false;

    await g.bank2.debit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      Number.parseInt(htlc2.amount),
      "Clearing",
    );
  });

  it("Basic usage of htlc with a transit account", async () => {
    //  Nostro of bank1 is funded and Bank1 wants to retrieve the funds
    // Bank2 needs a transit account to receive the funds
    const transitAccount = await createAccount("Transit", g.bank2, g.bo2User);

    // credit nostro bank 1
    await g.bank2.credit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      500_000,
      "Nostro funding",
    );
    // allow bank1 to operate its nostro
    await g.nostroBank1.whitelist(g.bo2User.send(), await g.bo1User.account());

    // Bank1 create secrets and all necessary elements
    const htlc1 = await createHTLCData();
    console.log("htlcData", htlc1);
    await g.nostroBank1.lockFunds(
      g.bo1User.send(),
      receipientInfo(),
      300_000,
      htlc1.timeout,
      htlc1.hash,
      htlc1.cancelHash,
      JSON.stringify({ tradeId: htlc1.tradeId, networkID: "POCR" }),
    );
    const logs = await getLogs(
      g.nostroBank1.events.HTLCPaymentCreated(g.bo1User.get(), {
        hashlockPaid: htlc1.hash,
      }),
    );
    expect(logs.length).to.equal(1);
    htlc1.id = logs[0].returnValues.id;
    console.log("htlcId", htlc1.id);
    // check the the funds are locked
    const balanceLocked = Number.parseInt(
      await g.nostroBank1.lockedBalance(g.bo1User.call()),
    );
    expect(balanceLocked).to.equal(300_000);

    // Bank2 has received the htlc id via the event and can make the payment
    const ev = cleanEvent(logs[0]).returnValues;
    const htlc2 = cleanStruct(
      await g.nostroBank1.getHTLCPayment(g.bo2User.call(), ev.id),
    );
    htlc2.id = ev.id;
    // making a successful payment in DL3S or other scheme reveals the secret
    htlc2.secret = htlc1.secret;
    console.log("htlc2", htlc2);
    // Bank2 can now claim the funds to cover its payment
    await g.nostroBank1.transferLockedFunds(
      g.bo2User.send(),
      htlc2.id,
      receipientInfo(transitAccount.deployedAt),
      htlc2.secret,
      "Redemption",
    );
    // And the funds are now in the transit account that can be cleared by Bank2
    const balance = await g.bank2.balanceOf(
      g.bo2User.call(),
      transitAccount.deployedAt,
    );
    expect(balance).to.equal(htlc2.amount);
    // check the event log
    const logs2 = await getLogs(
      g.nostroBank1.events.HTLCPaymentRemoved(g.bo2User.get(), {
        id: htlc2.id,
      }),
    );
    expect(logs2.length).to.equal(1);
    expect(logs2[0].returnValues.cancelled).to.be.false;

    await g.bank2.debit(
      g.bo2User.send(),
      transitAccount.deployedAt,
      Number.parseInt(htlc2.amount),
      "Clearing",
    );
  });

  it("Basic usage of htlc with a transfer to the BIC of the bank", async () => {
    //  Nostro of bank1 is funded and Bank1 wants to retrieve the funds

    // credit nostro bank 1
    await g.bank2.credit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      500_000,
      "Nostro funding",
    );
    // allow bank1 to operate its nostro
    await g.nostroBank1.whitelist(g.bo2User.send(), await g.bo1User.account());

    // Bank1 create secrets and all necessary elements
    const htlc1 = await createHTLCData();
    console.log("htlcData", htlc1);
    await g.nostroBank1.lockFunds(
      g.bo1User.send(),
      receipientInfo(),
      300_000,
      htlc1.timeout,
      htlc1.hash,
      htlc1.cancelHash,
      JSON.stringify({ tradeId: htlc1.tradeId, networkID: "POCR" }),
    );
    const logs = await getLogs(
      g.nostroBank1.events.HTLCPaymentCreated(g.bo1User.get(), {
        hashlockPaid: htlc1.hash,
      }),
    );
    expect(logs.length).to.equal(1);
    htlc1.id = logs[0].returnValues.id;
    console.log("htlcId", htlc1.id);
    // check the the funds are locked
    const balanceLocked = Number.parseInt(
      await g.nostroBank1.lockedBalance(g.bo1User.call()),
    );
    expect(balanceLocked).to.equal(300_000);

    // Bank2 has received the htlc id via the event and can make the payment
    const ev = cleanEvent(logs[0]).returnValues;
    const htlc2 = cleanStruct(
      await g.nostroBank1.getHTLCPayment(g.bo2User.call(), ev.id),
    );
    htlc2.id = ev.id;
    // making a successful payment in DL3S or other scheme reveals the secret
    htlc2.secret = htlc1.secret;
    console.log("htlc2", htlc2);
    // Bank2 can now claim the funds to cover its payment
    const bic = await g.bank2.bic(g.bo2User.call());
    await g.nostroBank1.transferLockedFunds(
      g.bo2User.send(),
      htlc2.id,
      receipientInfo(undefined, bic, ""),
      htlc2.secret,
      "Redemption",
    );
    // And the funds are now in the transit account that can be cleared by Bank2
    const balance = Number.parseInt(
      await g.bank2.balanceOf(g.bo2User.call(), g.nostroBank1.deployedAt),
    );
    expect(balance).to.equal(500_000 - htlc2.amount);
    // check the event log
    const logs2 = await getLogs(
      g.nostroBank1.events.HTLCPaymentRemoved(g.bo2User.get(), {
        id: htlc2.id,
      }),
    );
    expect(logs2.length).to.equal(1);
    expect(logs2[0].returnValues.cancelled).to.be.false;
  });

  it("Can cancel the lock with the secret", async () => {
    // credit nostro bank 1
    await g.bank2.credit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      500_000,
      "Nostro funding",
    );
    // allow bank1 to operate its nostro
    await g.nostroBank1.whitelist(g.bo2User.send(), await g.bo1User.account());

    // Bank1 create secrets and all necessary elements
    const htlc1 = await createHTLCData();
    await g.nostroBank1.lockFunds(
      g.bo1User.send(),
      receipientInfo(),
      300_000,
      htlc1.timeout,
      htlc1.hash,
      htlc1.cancelHash,
      JSON.stringify({ tradeId: htlc1.tradeId, networkID: "POCR" }),
    );
    const logs = await getLogs(
      g.nostroBank1.events.HTLCPaymentCreated(g.bo1User.get(), {
        hashlockPaid: htlc1.hash,
      }),
    );
    htlc1.id = logs[0].returnValues.id;
    // check the the funds are locked
    let balanceLocked = Number.parseInt(
      await g.nostroBank1.lockedBalance(g.bo1User.call()),
    );
    expect(balanceLocked).to.equal(300_000);

    // Bank1 can cancel the lock
    await g.nostroBank1.unlockFunds(
      g.bo1User.send(),
      htlc1.id,
      htlc1.cancelSecret,
    );
    balanceLocked = Number.parseInt(
      await g.nostroBank1.lockedBalance(g.bo1User.call()),
    );
    expect(balanceLocked).to.equal(0);
    // check the event log
    const logs2 = await getLogs(
      g.nostroBank1.events.HTLCPaymentRemoved(g.bo2User.get(), {
        id: htlc1.id,
      }),
    );
    expect(logs2.length).to.equal(1);
    expect(logs2[0].returnValues.cancelled).to.be.true;
  });

  it("A client locks its fund to execute a dvp with another chain", async () => {
    // Create client 1 and 2 accounts
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank2, g.bo2User);
    // allows the clients to operate their account without the bank
    await account1.whitelist(g.bo1User.send(), await g.user1.account());
    await account2.whitelist(g.bo2User.send(), await g.user2.account());

    // Client 1 has locked the asset on the other chain and provided a hash to client 2
    const { hash, timeout, secret } = await createHTLCData();

    // Client 2 has a credit and can lock the necessary funds to execute the DVP using this hash
    await g.bank2.credit(
      g.bo2User.send(),
      account2.deployedAt,
      500_000,
      "Client 2 funding",
    );
    await account2.lockFunds(
      g.user2.send(),
      receipientInfo(),
      300_000,
      timeout,
      hash,
      "0x0",
      JSON.stringify({ tradeId: "DVP1", networkID: "POCR" }),
    );

    // Client 1 receives the event and checks the lock
    let logs = await getLogs(
      account2.events.HTLCPaymentCreated(g.user1.get(), { hashlockPaid: hash }),
    );
    let ev = cleanEvent(logs[0]).returnValues;
    console.log("DvP Cash Lock", ev);
    // Client 1 is satisfied with the lock and retrieve the cash revealing the secret
    await account2.transferLockedFunds(
      g.user1.send(),
      ev.id,
      receipientInfo(account1.deployedAt),
      secret,
      "Pay DvP",
    );

    // Client 2 receives the secret and cat take the asset with it
    logs = await getLogs(
      account2.events.HTLCPaymentRemoved(g.user2.get(), { id: ev.id }),
    );
    ev = cleanEvent(logs[0]).returnValues;
    console.log("DvP Cash Lock released secret", ev.usingSecret);
    // Client 2 can now take the asset
  });

  it("Can make a PvP between 2 currencies in so|cash", async () => {
    // first recreate USD account on top of the EUR already created
    const eur = g;
    const usd = await prepareContracts(web3, "USD", false);

    // The setup will be for Client 1 @ Bank1 to sell EUR to Client 2 @ Bank2 and receive USD
    const account1EUR = await createAccount(
      "Account1EUR",
      eur.bank1,
      eur.bo1User,
    );
    const account1USD = await createAccount(
      "Account1USD",
      usd.bank1,
      usd.bo1User,
    );
    const account2EUR = await createAccount(
      "Account2EUR",
      eur.bank2,
      eur.bo2User,
    );
    const account2USD = await createAccount(
      "Account2USD",
      usd.bank2,
      usd.bo2User,
    );
    // allow the users
    await account1EUR.whitelist(eur.bo1User.send(), await g.user1.account());
    await account1USD.whitelist(usd.bo1User.send(), await g.user1.account());
    await account2EUR.whitelist(eur.bo2User.send(), await g.user2.account());
    await account2USD.whitelist(usd.bo2User.send(), await g.user2.account());

    // Clients have some credit on their account
    await eur.bank1.credit(
      eur.bo1User.send(),
      account1EUR.deployedAt,
      500_000,
      "Client 1 EUR funding",
    );
    await usd.bank2.credit(
      usd.bo2User.send(),
      account2USD.deployedAt,
      500_000,
      "Client 2 USD funding",
    );

    // Both parties have agreed on a price and a tradeId
    const tradeId = "PvP-1234";

    // Prepare the PvP on the Client 1 side, Client 1 locks its EUR
    const eurHTLC = await createHTLCData();
    await account1EUR.lockFunds(
      g.user1.send(),
      receipientInfo(),
      300_000,
      eurHTLC.timeout,
      eurHTLC.hash,
      eurHTLC.cancelHash,
      JSON.stringify({ tradeId, price: 1.2 }),
    );

    // Client 2 receives the event and prepare its side of the PvP
    let logs = await getLogs(
      g.accountContract.events.HTLCPaymentCreated(g.user2.get(), {}),
    );
    logs = logs.filter(
      (l) => JSON.parse(l.returnValues.htlc.opaque).tradeId === tradeId,
    );
    if (logs.length === 0) throw new Error("No event found for the EUR PvP");
    let htlcEUR = cleanEvent(logs[0]).returnValues;
    console.log("PvP Cash Lock", htlcEUR);
    // Client 2 locks its USD
    const eurAmount = Number.parseInt(htlcEUR.htlc.amount);
    const price = JSON.parse(htlcEUR.htlc.opaque).price;
    const usdAmount = Math.round(eurAmount * price);
    const deadline = Number.parseInt(htlcEUR.htlc.deadline) - 30; // 30 seconds before the deadline
    console.log("PvP Cash Lock", eurAmount, usdAmount, deadline);
    await account2USD.lockFunds(
      g.user2.send(),
      receipientInfo(),
      usdAmount,
      deadline,
      htlcEUR.htlc.hashlockPaid,
      htlcEUR.htlc.hashlockCancel,
      htlcEUR.htlc.opaque,
    );

    // Client 1 receives the event and checks the lock
    logs = await getLogs(
      account2USD.events.HTLCPaymentCreated(g.user1.get(), {
        hashlockPaid: eurHTLC.hash,
      }),
    );
    if (logs.length === 0) throw new Error("No event found for the USD PvP");
    const htlcUSD = cleanEvent(logs[0]).returnValues;
    // Client 1 transfer the USD to its account revealing the secret
    await account2USD.transferLockedFunds(
      g.user1.send(),
      htlcUSD.id,
      receipientInfo(account1USD.deployedAt),
      eurHTLC.secret,
      "Pay PvP",
    );

    // Client 2 receives the secret and can now take the EUR
    logs = await getLogs(
      g.accountContract.events.HTLCPaymentRemoved(g.user2.get(), {
        id: htlcUSD.id,
      }),
    );
    const ev3 = cleanEvent(logs[0]).returnValues;
    console.log("PvP Cash Lock released secret", ev3.usingSecret);
    // Client 2 can now take the EUR
    await account1EUR.transferLockedFunds(
      g.user2.send(),
      htlcEUR.id,
      receipientInfo(account2EUR.deployedAt),
      ev3.usingSecret,
      "Pay PvP",
    );
  });

  it("Can cancel the lock after the deadline without the secret", async () => {
    // credit nostro bank 1
    await g.bank2.credit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      500_000,
      "Nostro funding",
    );
    // allow bank1 to operate its nostro
    await g.nostroBank1.whitelist(g.bo2User.send(), await g.bo1User.account());

    // Bank1 create secrets and all necessary elements
    const htlc1 = await createHTLCData();
    await g.nostroBank1.lockFunds(
      g.bo1User.send(),
      receipientInfo(),
      300_000,
      htlc1.timeout,
      htlc1.hash,
      htlc1.cancelHash,
      JSON.stringify({ tradeId: htlc1.tradeId, networkID: "POCR" }),
    );
    const logs = await getLogs(
      g.nostroBank1.events.HTLCPaymentCreated(g.bo1User.get(), {
        hashlockPaid: htlc1.hash,
      }),
    );
    htlc1.id = logs[0].returnValues.id;

    await mineBlock(htlc1.timeout + 1);
    // Bank1 can cancel the lock
    await g.nostroBank1.unlockFunds(g.bo1User.send(), htlc1.id, "");
    const balanceLocked = Number.parseInt(
      await g.nostroBank1.lockedBalance(g.bo1User.call()),
    );
    expect(balanceLocked).to.equal(0);
    // check the event log
    const logs2 = await getLogs(
      g.nostroBank1.events.HTLCPaymentRemoved(g.bo2User.get(), {
        id: htlc1.id,
      }),
    );
    expect(logs2.length).to.equal(1);
    expect(logs2[0].returnValues.cancelled).to.be.true;
  });

  it("Cannot transfer the locked funds without a valid secret", async () => {
    // credit nostro bank 1
    await g.bank2.credit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      500_000,
      "Nostro funding",
    );
    // allow bank1 to operate its nostro
    await g.nostroBank1.whitelist(g.bo2User.send(), await g.bo1User.account());

    // Bank1 create secrets and all necessary elements
    const htlc1 = await createHTLCData();
    await g.nostroBank1.lockFunds(
      g.bo1User.send(),
      receipientInfo(),
      300_000,
      htlc1.timeout,
      htlc1.hash,
      htlc1.cancelHash,
      JSON.stringify({ tradeId: htlc1.tradeId, networkID: "POCR" }),
    );
    const logs = await getLogs(
      g.nostroBank1.events.HTLCPaymentCreated(g.bo1User.get(), {
        hashlockPaid: htlc1.hash,
      }),
    );
    htlc1.id = logs[0].returnValues.id;

    // try transfering the funds with an incorrect secret
    const p = g.nostroBank1.transferLockedFunds(
      g.bo2User.send(),
      htlc1.id,
      receipientInfo(g.nostroBank2.deployedAt),
      "a false secret",
      "Redemption",
    );
    await expect(p).to.be.rejectedWith("secret mismatch");
  });
});
