async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deployer:', deployer.address);

  const Token = await ethers.getContractFactory('PIMToken');
  const token = await Token.deploy();
  await token.deployed();

  console.log('PIMToken deployed:', token.address);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
