import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanStructAndMap,
  ganacheProvider,
  setMochaTimeout,
} from "@so-cash/sc-shared/utils";
import {
  createAndRegisterNostro,
  createStablecoin,
  declareBank,
  declareReferentials,
  initContractCompilation,
  registerERC20Nostro,
  setCorrespondent,
  simulateEndToEndTransfer,
  unsubscribeAll,
} from "./so-cash-prepare";
import {
  bankIdentifier,
  createAccount,
  receipientInfo,
} from "@so-cash/sc-shared";

describe("SoCash Interbank scenarios", async function () {
  setMochaTimeout(this, 40_000);
  const web3 = new Web3(ganacheProvider() as any);
  let ref: Awaited<ReturnType<typeof declareReferentials>>;

  this.beforeEach(async () => {
    initContractCompilation(true);
    ref = await declareReferentials(web3, true, "FR", "US");
  });
  this.afterEach(() => {
    unsubscribeAll();
  });

  it("One bank standalone to control the deployment", async () => {
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
  });

  it("Two bank setup with reciprocal correspondent nostro accounts", async () => {
    // create two banks
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bank2 = await declareBank(
      web3,
      ref,
      "BOFAUS3N",
      bankIdentifier("US", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );

    // create the nostro accounts for each
    const bank1Nostro = await createAndRegisterNostro(
      ref,
      bank1,
      bank2,
      "Bank1Nostro",
      true,
      true,
    );
    const bank2Nostro = await createAndRegisterNostro(
      ref,
      bank2,
      bank1,
      "Bank2Nostro",
      true,
      true,
    );
    // declare the correspondent relations
    await setCorrespondent(ref, bank1, bank2);
    await setCorrespondent(ref, bank2, bank1);

    // create 2 clients accounts
    const client1 = await createAccount("Client1", bank1.bank, bank1.boUser);
    const client2 = await createAccount("Client2", bank2.bank, bank2.boUser);

    // Initiate a balance on client 1 account
    await bank1.bank.credit(
      bank1.boUser.send(),
      client1.deployedAt,
      1_000_00,
      "Funding",
    );

    // Transfer from client1 to client2
    await client1.transferEx(
      bank1.boUser.send(),
      receipientInfo(client2.deployedAt),
      500_00,
      "Transfer",
    );

    // Check the balances
    let [
      client1Balance,
      client2Balance,
      bank1NostroBalance,
      bank2NostroBalance,
    ] = (
      await Promise.all([
        client1.fullBalance(bank1.boUser.call()),
        client2.fullBalance(bank2.boUser.call()),
        bank1Nostro.fullBalance(bank1.boUser.call()),
        bank2Nostro.fullBalance(bank2.boUser.call()),
      ])
    ).map((b) => Number.parseInt(b));
    console.log("Balances:", {
      client1Balance,
      client2Balance,
      nostro1Balance: bank1NostroBalance,
      nostro2Balance: bank2NostroBalance,
    });

    expect(client1Balance).to.equal(500_00);
    expect(client2Balance).to.equal(500_00);
    expect(bank1NostroBalance).to.equal(0);
    expect(bank2NostroBalance).to.equal(500_00);

    // Reveerse the payment to use the balance of bank1Nostro
    await client2.transferEx(
      bank2.boUser.send(),
      receipientInfo(client1.deployedAt),
      300_00,
      "Transfer 2",
    );

    [client1Balance, client2Balance, bank1NostroBalance, bank2NostroBalance] = (
      await Promise.all([
        client1.fullBalance(bank1.boUser.call()),
        client2.fullBalance(bank2.boUser.call()),
        bank1Nostro.fullBalance(bank1.boUser.call()),
        bank2Nostro.fullBalance(bank2.boUser.call()),
      ])
    ).map((b) => Number.parseInt(b));
    console.log("Balances:", {
      client1Balance,
      client2Balance,
      nostro1Balance: bank1NostroBalance,
      nostro2Balance: bank2NostroBalance,
    });
    expect(client1Balance).to.equal(800_00);
    expect(client2Balance).to.equal(200_00);
    expect(bank1NostroBalance).to.equal(0);
    expect(bank2NostroBalance).to.equal(200_00);
  });

  it("Two bank setup with correspondent and Stablecoin nostros", async () => {
    // create two banks
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bank2 = await declareBank(
      web3,
      ref,
      "BOFAUS3N",
      bankIdentifier("US", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );
    // create the stablecoin
    const stablecoin = await createStablecoin(web3, "EUR", 0, 2, true);

    // declare the nostro accounts as address in the stablecoin

    await registerERC20Nostro(ref, bank1, stablecoin, true);
    await registerERC20Nostro(ref, bank2, stablecoin, true);

    // declare the correspondent relations
    await setCorrespondent(ref, bank1, bank2);
    await setCorrespondent(ref, bank2, bank1);

    // Give some stablecoin to bank1
    await stablecoin.contract.mint(
      stablecoin.owner.send(),
      bank1.bank.deployedAt,
      10_000_00,
    );

    // create 2 clients accounts
    const client1 = await createAccount("Client1", bank1.bank, bank1.boUser);
    const client2 = await createAccount("Client2", bank2.bank, bank2.boUser);

    // Initiate a balance on client 1 account
    await bank1.bank.credit(
      bank1.boUser.send(),
      client1.deployedAt,
      1_000_00,
      "Funding",
    );

    const simulatedPlan = await simulateEndToEndTransfer(
      bank1,
      client1,
      receipientInfo(client2.deployedAt),
      0,
    );
    console.log(
      "SIMULATED PLAN",
      JSON.stringify(cleanStructAndMap(simulatedPlan), null, 2),
    );

    // Transfer from client1 to client2
    await client1.transferEx(
      bank1.boUser.send(),
      receipientInfo(client2.deployedAt),
      500_00,
      "Transfer",
    );

    // collect and control the balances
    let [
      client1Balance,
      client2Balance,
      bank1NostroBalance,
      bank2NostroBalance,
    ] = (
      await Promise.all([
        client1.fullBalance(bank1.boUser.call()),
        client2.fullBalance(bank2.boUser.call()),
        stablecoin.contract.balanceOf(
          bank1.boUser.call(),
          bank1.bank.deployedAt,
        ),
        stablecoin.contract.balanceOf(
          bank2.boUser.call(),
          bank2.bank.deployedAt,
        ),
      ])
    ).map((b) => Number.parseInt(b));
    console.log("Balances:", {
      client1Balance,
      client2Balance,
      bank1NostroBalance,
      bank2NostroBalance,
    });
    expect(client1Balance).to.equal(500_00);
    expect(client2Balance).to.equal(500_00);
    expect(bank1NostroBalance).to.equal(9_500_00);
    expect(bank2NostroBalance).to.equal(500_00);

    // Reveerse the payment to use the balance of bank2 in the stablecoin
    await client2.transferEx(
      bank2.boUser.send(),
      receipientInfo(client1.deployedAt),
      300_00,
      "Transfer 2",
    );
    // collect and control the balances
    [client1Balance, client2Balance, bank1NostroBalance, bank2NostroBalance] = (
      await Promise.all([
        client1.fullBalance(bank1.boUser.call()),
        client2.fullBalance(bank2.boUser.call()),
        stablecoin.contract.balanceOf(
          bank1.boUser.call(),
          bank1.bank.deployedAt,
        ),
        stablecoin.contract.balanceOf(
          bank2.boUser.call(),
          bank2.bank.deployedAt,
        ),
      ])
    ).map((b) => Number.parseInt(b));
    console.log("Balances:", {
      client1Balance,
      client2Balance,
      bank1NostroBalance,
      bank2NostroBalance,
    });
    expect(client1Balance).to.equal(800_00);
    expect(client2Balance).to.equal(200_00);
    expect(bank1NostroBalance).to.equal(9_800_00);
    expect(bank2NostroBalance).to.equal(200_00);
  });

  it("Two bank setup with correspondent and so|cash shared bank", async () => {
    // create two banks
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bank2 = await declareBank(
      web3,
      ref,
      "BOFAUS3N",
      bankIdentifier("US", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );
    // create the central bank

    const centralBank = await declareBank(
      web3,
      ref,
      "CENTRALB",
      bankIdentifier("FR", ["00000", "00000"]),
      "EUR",
      2,
      true,
    );

    // declare the nostro accounts in the central bank

    const nostro1 = await createAndRegisterNostro(
      ref,
      bank1,
      centralBank,
      "Nostro1",
      true,
      true,
    );
    const nostro2 = await createAndRegisterNostro(
      ref,
      bank2,
      centralBank,
      "Nostro2",
      true,
      true,
    );

    // declare the correspondent relations
    await setCorrespondent(ref, bank1, bank2);
    await setCorrespondent(ref, bank2, bank1);

    // Give some CeBM to Bank1
    await centralBank.bank.credit(
      centralBank.boUser.send(),
      nostro1.deployedAt,
      10_000_00,
      "Funding",
    );

    // create 2 clients accounts
    const client1 = await createAccount("Client1", bank1.bank, bank1.boUser);
    const client2 = await createAccount("Client2", bank2.bank, bank2.boUser);

    // Initiate a balance on client 1 account
    await bank1.bank.credit(
      bank1.boUser.send(),
      client1.deployedAt,
      1_000_00,
      "Funding",
    );
    console.log(
      "Nostro Bank1 balances",
      await bank1.bank.getNostroBalance(
        bank1.boUser.call(),
        centralBank.bank.deployedAt,
        nostro1.deployedAt,
      ),
    );

    const simulatedTransfer = await simulateEndToEndTransfer(
      bank1,
      client1,
      receipientInfo(client2.deployedAt),
      500_00,
    );
    console.log(
      "SIMULATED PLAN:",
      JSON.stringify(cleanStructAndMap(simulatedTransfer), null, 2),
    );

    // Transfer from client1 to client2
    await client1.transferEx(
      bank1.boUser.send(),
      receipientInfo(client2.deployedAt),
      500_00,
      "Transfer",
    );

    // collect and control the balances
    let [
      client1Balance,
      client2Balance,
      bank1NostroBalance,
      bank2NostroBalance,
    ] = (
      await Promise.all([
        client1.fullBalance(bank1.boUser.call()),
        client2.fullBalance(bank2.boUser.call()),
        nostro1.fullBalance(bank1.boUser.call()),
        nostro2.fullBalance(bank2.boUser.call()),
      ])
    ).map((b) => Number.parseInt(b));
    console.log("Balances:", {
      client1Balance,
      client2Balance,
      bank1NostroBalance,
      bank2NostroBalance,
    });
    expect(client1Balance).to.equal(500_00);
    expect(client2Balance).to.equal(500_00);
    expect(bank1NostroBalance).to.equal(9_500_00);
    expect(bank2NostroBalance).to.equal(500_00);

    // Reveerse the payment to use the balance of bank2 in the stablecoin
    await client2.transferEx(
      bank2.boUser.send(),
      receipientInfo(client1.deployedAt),
      300_00,
      "Transfer 2",
    );
    // collect and control the balances
    [client1Balance, client2Balance, bank1NostroBalance, bank2NostroBalance] = (
      await Promise.all([
        client1.fullBalance(bank1.boUser.call()),
        client2.fullBalance(bank2.boUser.call()),
        nostro1.fullBalance(bank1.boUser.call()),
        nostro2.fullBalance(bank2.boUser.call()),
      ])
    ).map((b) => Number.parseInt(b));
    console.log("Balances:", {
      client1Balance,
      client2Balance,
      bank1NostroBalance,
      bank2NostroBalance,
    });
    expect(client1Balance).to.equal(800_00);
    expect(client2Balance).to.equal(200_00);
    expect(bank1NostroBalance).to.equal(9_800_00);
    expect(bank2NostroBalance).to.equal(200_00);
  });

  it("Four banks setup with correspondent and Stablecoin nostros", async () => {
    // create two banks connected to central bank (stable coin)
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bank2 = await declareBank(
      web3,
      ref,
      "BOFAUS3N",
      bankIdentifier("US", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );

    // create the stablecoin representing central bank money
    const stablecoin = await createStablecoin(web3, "EUR", 0, 2, true);

    // declare the nostro accounts as address in the stablecoin

    await registerERC20Nostro(ref, bank1, stablecoin, true);
    await registerERC20Nostro(ref, bank2, stablecoin, true);

    // declare the correspondent relations between the 2 banks
    await setCorrespondent(ref, bank1, bank2);
    await setCorrespondent(ref, bank2, bank1);

    // create bankA, client of bank1
    const bankA = await declareBank(
      web3,
      ref,
      "AGRIFRPA",
      bankIdentifier("FR", ["10001", "11112"]),
      "EUR",
      2,
      true,
    );
    const nostroA = await createAndRegisterNostro(
      ref,
      bankA,
      bank1,
      "BankANostro",
      true,
      true,
    );
    await setCorrespondent(ref, bankA, bank1);
    // this is needed for the moment although it is not completely logical since the bankA will use its account at bank1.
    // BankA is not per say a correspondent of Bank1, but rather a client of Bank1.
    // But the resolveRoute does not see that yet.
    await setCorrespondent(ref, bank1, bankA);

    // create bankB, client of bank2
    const bankB = await declareBank(
      web3,
      ref,
      "BOFAUS3B",
      bankIdentifier("US", ["20001", "22223"]),
      "EUR",
      2,
      true,
    );
    const nostroB = await createAndRegisterNostro(
      ref,
      bankB,
      bank2,
      "BankBNostro",
      true,
      true,
    );
    await setCorrespondent(ref, bankB, bank2);

    // create 2 clients accounts in BankA and BankB
    const clientA = await createAccount("ClientA", bankA.bank, bankA.boUser);
    const clientB = await createAccount("ClientB", bankB.bank, bankB.boUser);

    // Set a balance in Bank1 stablecoin account
    await stablecoin.contract.mint(
      stablecoin.owner.send(),
      bank1.bank.deployedAt,
      10_000_00,
    );

    // Give money to BankA in Bank1
    await bank1.bank.credit(
      bank1.boUser.send(),
      nostroA.deployedAt,
      5_000_00,
      "Funding",
    );

    // Give money to ClientA in BankA
    await bankA.bank.credit(
      bankA.boUser.send(),
      clientA.deployedAt,
      1_000_00,
      "Funding",
    );

    // Test the route resolution
    // const route = await ref.root.resolveRoute(
    //   ref.rootUser.call(),
    //   toBuffer(bankA.ccy, 3),
    //   bankA.id,
    //   bankB.id
    // );
    // console.log("Route", JSON.stringify(route, null, 2));

    const simulatedPlan = await simulateEndToEndTransfer(
      bankA,
      clientA,
      receipientInfo(clientB.deployedAt),
      500_00,
    );
    console.log(
      "SIMULATED PLAN",
      JSON.stringify(cleanStructAndMap(simulatedPlan), null, 2),
    );

    // Transfer from ClientA to ClientB
    const tx = await clientA.transferEx(
      bankA.boUser.send(),
      receipientInfo(clientB.deployedAt),
      500_00,
      "Transfer",
    );
    const detail = await web3.eth.getTransactionReceipt(tx);
    console.log("Transfer gas consumed", detail.gasUsed);

    // collect and control the balances
    let [
      clientABalance,
      clientBBalance,
      bankANostroBalance,
      bank1NostroBalance,
      bank2NostroBalance,
      bankBNostroBalance,
    ] = (
      await Promise.all([
        clientA.fullBalance(bankA.boUser.call()),
        clientB.fullBalance(bankB.boUser.call()),
        nostroA.fullBalance(bankA.boUser.call()),
        stablecoin.contract.balanceOf(
          bank1.boUser.call(),
          bank1.bank.deployedAt,
        ),
        stablecoin.contract.balanceOf(
          bank2.boUser.call(),
          bank2.bank.deployedAt,
        ),
        nostroB.fullBalance(bankB.boUser.call()),
      ])
    ).map((b) => Number.parseInt(b));
    console.log("Balances:", {
      clientABalance,
      clientBBalance,
      bankANostroBalance,
      bank1NostroBalance,
      bank2NostroBalance,
      bankBNostroBalance,
    });
    expect(clientABalance).to.equal(500_00);
    expect(clientBBalance).to.equal(500_00);
    expect(bankANostroBalance).to.equal(4_500_00);
    expect(bank1NostroBalance).to.equal(9_500_00);
    expect(bank2NostroBalance).to.equal(500_00);
    expect(bankBNostroBalance).to.equal(500_00);
  });

  it("Three banks setup with a risk of circular route", async () => {
    // create the 3 banks A, B and C
    const bankA = await declareBank(
      web3,
      ref,
      "AGRIFRPA",
      bankIdentifier("FR", ["10001", "11112"]),
      "EUR",
      2,
      true,
    );
    const bankB = await declareBank(
      web3,
      ref,
      "BOFAUS3B",
      bankIdentifier("US", ["20001", "22223"]),
      "EUR",
      2,
      true,
    );
    const bankC = await declareBank(
      web3,
      ref,
      "AGRIFRPC",
      bankIdentifier("FR", ["30002", "33334"]),
      "EUR",
      2,
      true,
    );

    // All banks open a nostro with each others and register bilateral correspondent relations
    // This is the setup we had in the previous version of so|cash
    const nostroAwithB = await createAndRegisterNostro(
      ref,
      bankA,
      bankB,
      "NostroAwithB",
      true,
      true,
    );
    await setCorrespondent(ref, bankA, bankB);
    const nostroAwithC = await createAndRegisterNostro(
      ref,
      bankA,
      bankC,
      "NostroAwithC",
      false,
      true,
    );
    await setCorrespondent(ref, bankA, bankC);
    const nostroBwithC = await createAndRegisterNostro(
      ref,
      bankB,
      bankC,
      "NostroBwithC",
      true,
      true,
    );
    await setCorrespondent(ref, bankB, bankC);
    const nostroBwithA = await createAndRegisterNostro(
      ref,
      bankB,
      bankA,
      "NostroBwithA",
      false,
      true,
    );
    await setCorrespondent(ref, bankB, bankA);
    const nostroCwithA = await createAndRegisterNostro(
      ref,
      bankC,
      bankA,
      "NostroCwithA",
      false,
      true,
    );
    await setCorrespondent(ref, bankC, bankA);
    const nostroCwithB = await createAndRegisterNostro(
      ref,
      bankC,
      bankB,
      "NostroCwithB",
      true,
      true,
    );
    await setCorrespondent(ref, bankC, bankB);

    // create 3 clients accounts in BankA, BankB and BankC
    const clientA = await createAccount("ClientA", bankA.bank, bankA.boUser);
    const clientB = await createAccount("ClientB", bankB.bank, bankB.boUser);
    const clientC = await createAccount("ClientC", bankC.bank, bankC.boUser);

    // Set a balance in NostroA with B
    await bankB.bank.credit(
      bankB.boUser.send(),
      nostroAwithB.deployedAt,
      1_000_00,
      "Funding",
    );

    // Set a balance in ClientA account
    await bankA.bank.credit(
      bankA.boUser.send(),
      clientA.deployedAt,
      1_000_00,
      "Funding",
    );

    // Transfer from ClientA to ClientB

    let plan = await bankA.bank.simulateTransfer(
      bankA.boUser.call(),
      clientA.deployedAt,
      receipientInfo(clientB.deployedAt),
      800_00,
    );
    console.log("plan: ClientA -> ClientB", cleanStructAndMap(plan));
    await clientA.transferEx(
      bankA.boUser.send(),
      receipientInfo(clientB.deployedAt),
      800_00,
      "Transfer",
    );
    // Transfer from ClientB to ClientC
    await clientB.transferEx(
      bankB.boUser.send(),
      receipientInfo(clientC.deployedAt),
      600_00,
      "Transfer",
    );
    // Transfer from ClientC to ClientA
    plan = await bankC.bank.simulateTransfer(
      bankC.boUser.call(),
      clientC.deployedAt,
      receipientInfo(clientA.deployedAt),
      400_00,
    );
    console.log("plan: ClientC -> ClientA", cleanStructAndMap(plan));
    await clientC.transferEx(
      bankC.boUser.send(),
      receipientInfo(clientA.deployedAt),
      400_00,
      "Transfer",
    );
    // Transfer from ClientA to ClientC

    plan = await bankA.bank.simulateTransfer(
      bankA.boUser.call(),
      clientA.deployedAt,
      receipientInfo(clientC.deployedAt),
      500_00,
    );
    console.log("plan: ClientA -> ClientC", cleanStructAndMap(plan));

    await clientA.transferEx(
      bankA.boUser.send(),
      receipientInfo(clientC.deployedAt),
      500_00,
      "Transfer",
    );
  });

  it("Four banks where correspondents settle in two different banks", async () => {
    // create the 4 banks Bank1, Bank2, BankA, BankB
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bank2 = await declareBank(
      web3,
      ref,
      "BOFAUS3N",
      bankIdentifier("US", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );

    // create reciprocal nostro between bank1 and bank2
    const nostro1with2 = await createAndRegisterNostro(
      ref,
      bank1,
      bank2,
      "Nostro1withBank2",
      true,
      true,
    );
    const nostro2with1 = await createAndRegisterNostro(
      ref,
      bank2,
      bank1,
      "Nostro2withBank1",
      true,
      true,
    );
    // declare the correspondent relations between the 2 banks
    await setCorrespondent(ref, bank1, bank2);
    await setCorrespondent(ref, bank2, bank1);

    // create bankA, client of bank1
    const bankA = await declareBank(
      web3,
      ref,
      "AGRIFRPA",
      bankIdentifier("FR", ["10001", "11112"]),
      "EUR",
      2,
      true,
    );
    const nostroA = await createAndRegisterNostro(
      ref,
      bankA,
      bank1,
      "BankANostro",
      true,
      true,
    );

    // create bankB, client of bank2
    const bankB = await declareBank(
      web3,
      ref,
      "BOFAUS3B",
      bankIdentifier("US", ["20001", "22223"]),
      "EUR",
      2,
      true,
    );
    const nostroB = await createAndRegisterNostro(
      ref,
      bankB,
      bank2,
      "BankBNostro",
      true,
      true,
    );
    await setCorrespondent(ref, bankA, bankB);
    await setCorrespondent(ref, bankB, bankA);

    // create 2 clients accounts in BankA and BankB
    const clientA = await createAccount("ClientA", bankA.bank, bankA.boUser);
    const clientB = await createAccount("ClientB", bankB.bank, bankB.boUser);

    // Set a balance in BankA account at Bank1
    await bank1.bank.credit(
      bank1.boUser.send(),
      nostroA.deployedAt,
      5_000_00,
      "Funding",
    );

    // Set a balance in ClientA account
    await bankA.bank.credit(
      bankA.boUser.send(),
      clientA.deployedAt,
      1_000_00,
      "Funding",
    );

    // Transfer from ClientA to ClientB
    await clientA.transferEx(
      bankA.boUser.send(),
      receipientInfo(clientB.deployedAt),
      400_00,
      "Transfer",
    );

    // collect and control the balances
    let [
      clientABalance,
      clientBBalance,
      bankANostroWithBk1Bal,
      bank1NostroWithBk2Bal,
      bank2NostroWithBk1Bal,
      bankBNostroWithBk2Bal,
    ] = (
      await Promise.all([
        clientA.fullBalance(bankA.boUser.call()),
        clientB.fullBalance(bankB.boUser.call()),
        nostroA.fullBalance(bankA.boUser.call()),
        nostro1with2.fullBalance(bank1.boUser.call()),
        nostro2with1.fullBalance(bank2.boUser.call()),
        nostroB.fullBalance(bankB.boUser.call()),
      ])
    ).map((b) => Number.parseInt(b));

    console.log("Balances:", {
      clientABalance,
      bankANostroWithBk1Bal,
      bank2NostroWithBk1Bal,
      bank1NostroWithBk2Bal,
      bankBNostroWithBk2Bal,
      clientBBalance,
    });

    expect(clientABalance).to.equal(600_00);
    expect(bankANostroWithBk1Bal).to.equal(4_600_00);
    expect(bank2NostroWithBk1Bal).to.equal(400_00);
    expect(bank1NostroWithBk2Bal).to.equal(0);
    expect(bankBNostroWithBk2Bal).to.equal(400_00);
    expect(clientBBalance).to.equal(400_00);
  });

  it("Four banks setup with a central bank, 2 main banks and a client bank", async () => {
    // create the 4 banks Bank1, Bank2, BankA, BankB
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bank2 = await declareBank(
      web3,
      ref,
      "BOFAFR3N",
      bankIdentifier("FR", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );

    // create the central bank
    const centralBank = await declareBank(
      web3,
      ref,
      "CENTRALB",
      bankIdentifier("FR", ["00000", "00000"]),
      "EUR",
      2,
      true,
    );

    // create the nostros of bank1 and bank2 with the central bank
    const nostro1 = await createAndRegisterNostro(
      ref,
      bank1,
      centralBank,
      "Nostro1",
      true,
      true,
    );
    const nostro2 = await createAndRegisterNostro(
      ref,
      bank2,
      centralBank,
      "Nostro2",
      true,
      true,
    );
    // create the correspondent relations
    await setCorrespondent(ref, bank1, bank2);
    await setCorrespondent(ref, bank2, bank1);

    // create bankA, client of bank1
    const bankA = await declareBank(
      web3,
      ref,
      "AGRIFRPA",
      bankIdentifier("FR", ["10001", "11112"]),
      "EUR",
      2,
      true,
    );
    const nostroA = await createAndRegisterNostro(
      ref,
      bankA,
      bank1,
      "BankANostro",
      false, // for the moment the nostro is not set as SSI
      true,
    );
    // make bank1 accept incoming transfers from bankA
    await setCorrespondent(ref, bank1, bankA);

    // create clientA in bankA
    const clientA = await createAccount("ClientA", bankA.bank, bankA.boUser);
    // create client2 in bank2
    const client2 = await createAccount("Client2", bank2.bank, bank2.boUser);

    // No cash in Nostro of bankA (should fail)
    // Cash in nostro of bank1
    await centralBank.bank.credit(
      centralBank.boUser.send(),
      nostro1.deployedAt,
      10_000_00,
      "Funding",
    );

    // cash in clientA account
    await bankA.bank.credit(
      bankA.boUser.send(),
      clientA.deployedAt,
      2_000_00,
      "Funding",
    );

    // Transfer from clientA to client2

    // // simulate the transfer
    // let plan = await bankA.bank.simulateTransfer(
    //   bankA.boUser.call(),
    //   clientA.deployedAt,
    //   receipientInfo(client2.deployedAt),
    //   300_00
    // );
    // console.log("plan: ClientA -> Client2", cleanStructAndMap(plan));

    const p = clientA.transferEx(
      bankA.boUser.send(),
      receipientInfo(client2.deployedAt),
      300_00,
      "Transfer",
    );
    await expect(p).to.be.rejectedWith(
      /No matching SSI account found for the paying bank/,
    );
  });

  it("Four banks setup with a central bank, 2 main banks and a client bank in another country using IBAN", async () => {
    // declare the central bank
    const centralBank = await declareBank(
      web3,
      ref,
      "CENTRALB",
      bankIdentifier("FR", ["00000", "00000"]),
      "EUR",
      2,
      true,
    );
    // declare the 2 main banks
    const bank1 = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bank2 = await declareBank(
      web3,
      ref,
      "BOFAFR3N",
      bankIdentifier("FR", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );
    // declare their nostro with the central bank
    const nostro1 = await createAndRegisterNostro(
      ref,
      bank1,
      centralBank,
      "Nostro1",
      true,
      true,
    );
    const nostro2 = await createAndRegisterNostro(
      ref,
      bank2,
      centralBank,
      "Nostro2",
      true,
      true,
    );
    // declare the correspondent relations
    await setCorrespondent(ref, bank1, bank2);
    await setCorrespondent(ref, bank2, bank1);

    // declare a bankA client of bank1 but in the US
    const bankA = await declareBank(
      web3,
      ref,
      "AGRIUSPA",
      bankIdentifier("US", ["10001", "11112"]),
      "EUR",
      2,
      true,
    );
    // create a nostro for bankA with bank1
    const nostroA = await createAndRegisterNostro(
      ref,
      bankA,
      bank1,
      "BankANostro",
      true,
      true,
    );
    // declare the correspondent relations
    await setCorrespondent(ref, bank1, bankA);
    await setCorrespondent(ref, bankA, bank1);

    // create clientA in bankA
    const clientA = await createAccount("ClientA", bankA.bank, bankA.boUser);
    // create client2 in bank2
    const client2 = await createAccount("Client2", bank2.bank, bank2.boUser);

    // Give cash to bank2 in central bank
    await centralBank.bank.credit(
      centralBank.boUser.send(),
      nostro2.deployedAt,
      10_000_00,
      "Funding",
    );

    // Give cash to client2 in bank2
    await bank2.bank.credit(
      bank2.boUser.send(),
      client2.deployedAt,
      2_000_00,
      "Funding",
    );

    // get the IBAN of the clientA account
    const iban = await clientA.iban(bankA.boUser.call());
    console.log("IBAN", iban);

    const simulatedTransfer = await simulateEndToEndTransfer(
      bank2,
      client2,
      receipientInfo(undefined, undefined, iban),
      300_00,
    );
    console.log(
      "SIMULATED TRANSFER:",
      JSON.stringify(cleanStructAndMap(simulatedTransfer), null, 2),
    );

    // make a transfer from client2 to clientA using the IBAN
    await client2.transferEx(
      bank2.boUser.send(),
      receipientInfo(undefined, undefined, iban),
      300_00,
      "Transfer",
    );
  });

  it("Two banks setup A client of B, B transfer from A account to a client of A", async () => {
    // create the two banks A and B
    const bankA = await declareBank(
      web3,
      ref,
      "AGRIFRPA",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bankB = await declareBank(
      web3,
      ref,
      "BOFAFR3N",
      bankIdentifier("FR", ["20000", "22222"]),
      "EUR",
      2,
      true,
    );

    // Open an account for bankA in bankB
    const nostroA = await createAndRegisterNostro(
      ref,
      bankA,
      bankB,
      "NostroA",
      true,
      true,
    );
    // declare the correspondent relations
    await setCorrespondent(ref, bankA, bankB);
    await setCorrespondent(ref, bankB, bankA);

    // create a clientA in bankA
    const client1 = await createAccount("Client1", bankA.bank, bankA.boUser);

    // Give cash to BankA in BankB
    await bankB.bank.credit(
      bankB.boUser.send(),
      nostroA.deployedAt,
      10_000_00,
      "Funding",
    );

    // Transfer from BankA nostro in BankB to Client1 in BankA
    await nostroA.transferEx(
      bankB.boUser.send(),
      receipientInfo(client1.deployedAt),
      500_00,
      "Transfer",
    );

    // collect and test the resulting balances
    let [client1Balance, bankANostroBalance] = (
      await Promise.all([
        client1.fullBalance(bankA.boUser.call()),
        nostroA.fullBalance(bankA.boUser.call()),
      ])
    ).map((b) => Number.parseInt(b));

    console.log("Balances:", {
      client1Balance,
      bankANostroBalance,
    });

    expect(client1Balance).to.equal(500_00);
    expect(bankANostroBalance).to.equal(10_000_00); // no change
  });
});
