const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Pontoon Bridge test", async () => {
    let bridge_bsc;
    let bridge_eth;
    let pool_1;
    let pool_2;

    beforeEach(async () => {
        [...account] = await ethers.getSigners();
    });


    it("STEP 1. Creating Bridge contract", async function () {
        const Bridge = await hre.ethers.getContractFactory("Bridge");
        const Pool = await hre.ethers.getContractFactory("Pool");
        bridge_bsc = await Bridge.deploy();
        bridge_eth = await Bridge.deploy();
        pool_1 = await Pool.deploy();
        pool_2 = await Pool.deploy();

        let pool_1_bridge_role = await pool_1.BRIDGE_ROLE();
        let pool_2_bridge_role = await pool_2.BRIDGE_ROLE();
        await pool_1.grantRole(pool_1_bridge_role, bridge_bsc.address);
        await pool_1.grantRole(pool_1_bridge_role, bridge_eth.address);
        await pool_1.grantRole(pool_2_bridge_role, bridge_bsc.address);
        await pool_1.grantRole(pool_2_bridge_role, bridge_eth.address);

        bridge_bsc.setPool(pool_1.address);
        bridge_eth.setPool(pool_2.address);
    });


    it("STEP 2. Creating ERC20 token contract", async function () {
        const ERC20Token = await hre.ethers.getContractFactory("ERC20tpl");
        USDT_BSC = await ERC20Token.deploy("USDT_BSC token", "USDT_BSC", "200000000000000000000000000");
        USDT_ETH = await ERC20Token.deploy("USDT_ETH token", "USDT_ETH", "200000000000000000000000000");
    });


    it("STEP 3. Add token to contract", async function () {
        await bridge_bsc.addCoin(USDT_BSC.address, "USDT_BSC");
        await bridge_bsc.addCoin(USDT_ETH.address, "USDT_ETH");

        await bridge_eth.addCoin(USDT_BSC.address, "USDT_BSC");
        await bridge_eth.addCoin(USDT_ETH.address, "USDT_ETH");

        let coin = await bridge_bsc.getCoinAddressBySymbol("USDT_BSC");
        expect(coin).to.equal(USDT_BSC.address);
        coin = await bridge_eth.getCoinAddressBySymbol("USDT_ETH");
        expect(coin).to.equal(USDT_ETH.address);

        await USDT_BSC.mint(account[0].address, ethers.utils.parseEther("1000.0"));
        await USDT_ETH.mint(account[0].address, ethers.utils.parseEther("1000.0"));
        await USDT_BSC.mint(pool_1.address, ethers.utils.parseEther("1000.0"));
        await USDT_ETH.mint(pool_2.address, ethers.utils.parseEther("1000.0"));
        let balance = await USDT_BSC.balanceOf(account[0].address);
        expect(balance).to.equal(ethers.utils.parseEther("1000.0"));
        balance = await USDT_ETH.balanceOf(account[0].address);
        expect(balance).to.equal(ethers.utils.parseEther("1000.0"));
    });
    

    it("STEP 4. Create swap", async function () {
        let transaction_number = 1;
        let amount = ethers.utils.parseEther("10.0");
        let symbol_to = "USDT_ETH";
        let symbol_from = "USDT_BSC";

        let message = transaction_number.toString() + amount.toString() + symbol_to.toString();

        signature = await account[0].signMessage(message);
        sig = ethers.utils.splitSignature(signature);

        await USDT_BSC.approve(bridge_bsc.address, ethers.utils.parseEther("10.0"));

        let res = await bridge_bsc.swap(
            transaction_number,
            amount,
            symbol_to, 
            symbol_from,
            sig.v,
            sig.r,
            sig.s
        );

        let balance = await USDT_BSC.balanceOf(pool_1.address);
        expect(balance).to.equal(ethers.utils.parseEther("1010.0"));

        balance = await USDT_BSC.balanceOf(account[0].address);
        expect(balance).to.equal(ethers.utils.parseEther("990.0"));

        balance = await USDT_ETH.balanceOf(account[0].address);
        expect(balance).to.equal(ethers.utils.parseEther("1000.0"));

        let state = await bridge_bsc.getSwapState(message);
        expect(state).to.equal(1);
    });

    it("STEP 5. Execute redeem", async function () {
        let transaction_number = 1;
        let amount = ethers.utils.parseEther("10.0");
        let symbol = "USDT_ETH";

        let message = transaction_number.toString() + amount.toString() + symbol.toString();

        signature = await account[0].signMessage(message);
        sig = ethers.utils.splitSignature(signature);


        let res = await bridge_eth.redeem( 
            transaction_number, 
            amount, 
            symbol, 
            sig.v,
            sig.r,
            sig.s
        );

        let balance_after = await USDT_ETH.balanceOf(account[0].address);
        expect(balance_after).to.equal(ethers.utils.parseEther("1010.0"));
    });

});