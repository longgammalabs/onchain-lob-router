// SPDX-License-Identifier: BUSL-1.1
// Central Limit Order Book (CLOB) exchange
// (c) Long Gamma Labs, 2023.


const ethers = require("ethers");
const routerInfo = require("./out/Router.sol/Router.json");

const rpcUrl = "CHANGE_ME";
const alicePk = "CHANGE_ME";

const provider = new ethers.JsonRpcProvider(rpcUrl);
const wallet = new ethers.Wallet(alicePk, provider);

async function main() {
    console.log("Deploying Router contract...");
	const routerAbi = routerInfo.abi;
    const routerBytecode = routerInfo.bytecode;
    const routerContractFactory = new ethers.ContractFactory(routerAbi, routerBytecode, wallet);
    const router = await routerContractFactory.deploy();
    await router.deploymentTransaction().wait();
    const routerAddress = router.target;
    console.log(`Router: ${routerAddress}`);
}

main()
.then(() => process.exit(0))
.catch((error) => {
    console.error(error);
    process.exit(1);
});
