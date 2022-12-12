# Blobs

#### TODO

- [ ] decide on pending values: initial mint list, pricing, BASE_URI
- [ ] make `GobblerTreasury` upgradeable after timelock? by DAO?
- [ ] deployment scripts
- [ ] ...

### Deployment

```sh
source .env

# goerli
forge script script/deploy/DeployGoerli.s.sol:Deployment --rpc-url goerli --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
# if verification fails with "Etherscan could not detect the deployment.". Resume script with `--resume` instead of `--broadcast`
```

## Resources

- https://sewer-kingdom-0x.notion.site/Requirements-9e7da5f9e03c4488a3f82b1d7dda5312