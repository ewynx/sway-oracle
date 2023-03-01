# A simple Oracle in Sway

From [this repo](https://github.com/sway-gang/price-oracle/blob/master/contract/src/main.sw) by Sway Gang. 

An Oracle provides external (off-chain) data to other Smart Contracts. 
In this simple Oracle Smart Contract we'll work with a trusted owner that can set the price of different assets, which can then be queried by anyone. 

## Install all the things

The easiest way to have everything simulateously up to date + easy switching between versions is with [fuelup](https://fuellabs.github.io/fuelup/master/). 

To use Sway, the Rust toolchain must be installed. This can be done withj [rustup](https://rustup.rs/). 

## Write Smart Contract

### Initialize project

``` forc new oracle ```

### Smart Contract Characteristics

Functions:
- owner; retrieve the currently set owner
- initialize; can only be called once and will set the owner
- set_price; for an asset_id, store the price_value that is given. Can only be executed by owner
- set_prices; batch set_price
- get_price; retrieve current price of given asset. Can be called by anyone

In storage the owner address and a StorageMap for prices per asset are stored. Specifically, there is a struct `Price` that holds `asset_id`, `price` and `last_update` (as timestamp), which is stored with every update and is the result of querying for this data. 

There are 2 custom errors: OwnerAlreadyInitialized and AccessDenied.

### Function details

#### owner

Retrieves owner from storage.
Output: Identity.

#### initialize

Sets the owner in storage to the given owner.
Input: owner (Address).

Errors: if owner has been set already (i.e. is no longer ZERO_b256).

#### set_price

Can only be called by owner. Saves the Price data for asset.
Input: asset_id (ContractId), price (u64).

Errors: if caller is not owner.

#### set_prices

Can only be called by owner. Saves the Price data for all assets.
Input: prices (Vec<(ContractId, u64)>).

Errors: if caller is not owner.

#### get_price

Retrieves data from storage. 
Input: asset_id (ContractId). Output: Option<Price>.

## Build 

```
forc build
```

Successful build gives something like:

```
  WARNING! unused manifest key: project.target
  Compiled library "core".
  Compiled library "std".
  Compiled contract "oracle".
  Bytecode size is 4228 bytes.
```

## Add tests

Create a testing environment:

```
cargo generate --init fuellabs/sway templates/sway-test-rs --name oracle --force
```

This generates the folder `tests` with a file called `harness.rs` and a config file `Cargo.toml`. 
To run the default testfile that has been given and creates an instance of the Oracle contract to run with, run `cargo test`. 

Within the test folder, create the folders:
local_test - for tests that run on a local node
utils - for helpful functions
token - for the token that we'll use for testing

### Test Token 

We need an asset to test with. In order to do that, we need a test contract for a Token and we'll add some test util code to be able to use it. 

In artefacts, create a folder token and [these files](https://github.com/sway-gang/price-oracle/tree/master/contract/tests/artefacts/token). You can also create a Token yourself.

### Test Utils

For the test token we need a pseudo random number library, install this with `cargo add rand`. 

The test utils contains code for:
- getting test Token contract instance (which is imported from `utils/token`)
- getting Oracle contract instance
- abstractions for the abi functions in the Oracle contract, making it easier to call them from the tests

In folder `utils` create files `mod.rs` and `local_test_utils.rs`. In `mod.rs` add 
```
pub mod local_test_utils;
```

In `local_test_utils.rs` add 3 pieces of code. For the test token:

```rust
use rand::prelude::Rng;

pub struct DeployTokenConfig {
    pub name: String,
    pub symbol: String,
    pub decimals: u8,
    pub mint_amount: u64,
}

pub async fn get_token_contract_instance(
    wallet: &WalletUnlocked,
    deploy_config: &DeployTokenConfig,
) -> TokenContract {
    let mut name = deploy_config.name.clone();
    let mut symbol = deploy_config.symbol.clone();
    let decimals = deploy_config.decimals;

    let mut rng = rand::thread_rng();
    let salt = rng.gen::<[u8; 32]>();

    let id = Contract::deploy_with_parameters(
        "./tests/token/token_contract.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::default(),
        Salt::from(salt),
    )
    .await
    .unwrap();

    let instance = TokenContract::new(id, wallet.clone());
    let methods = instance.methods();

    let mint_amount = parse_units(deploy_config.mint_amount, decimals);
    name.push_str(" ".repeat(32 - deploy_config.name.len()).as_str());
    symbol.push_str(" ".repeat(8 - deploy_config.symbol.len()).as_str());

    let config: token_contract_mod::Config = token_contract_mod::Config {
        name: SizedAsciiString::<32>::new(name).unwrap(),
        symbol: SizedAsciiString::<8>::new(symbol).unwrap(),
        decimals,
    };

    let _res = methods
        .initialize(config, mint_amount, Address::from(wallet.address()))
        .call()
        .await;
    let _res = methods.mint().append_variable_outputs(1).call().await;

    instance
}
```

For the Oracle contract and generally to get a wallet:

```rust
pub async fn init_wallet() -> WalletUnlocked {
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(1),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await;
    wallets.pop().unwrap()
}

pub async fn get_oracle_contract_instance(wallet: &WalletUnlocked) -> OracleContract {
    let id = Contract::deploy(
        "./out/debug/oracle.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::default(),
    )
    .await
    .unwrap();

    OracleContract::new(id, wallet.clone())
}
```

Finally, the abi calls can be abstracted like this: 
```rust
pub async fn initialize(contract: &OracleContract, owner: Address) -> FuelCallResponse<()> {
    contract.methods().initialize(owner).call().await.unwrap()
}

pub async fn get_price(contract: &OracleContract, asset_id: ContractId) -> Option<Price> {
    contract
        .methods()
        .get_price(asset_id)
        .call()
        .await
        .unwrap()
        .value
}

pub async fn set_price(
    contract: &OracleContract,
    asset_id: ContractId,
    new_price: u64,
) -> FuelCallResponse<()> {
    contract
        .methods()
        .set_price(asset_id, new_price)
        .call()
        .await
        .unwrap()
}
```

The full file looks like:
```rust
use fuels::prelude::*;
use rand::prelude::Rng;

abigen!(
    Contract(name = "OracleContract", abi = "out/debug/oracle-abi.json"),
    Contract(
        name = "TokenContract",
        abi = "tests/token/token_contract-abi.json"
    )
);

pub fn parse_units(num: u64, decimals: u8) -> u64 {
  num * 10u64.pow(decimals as u32)
}

pub mod abi_calls {
    use fuels::programs::call_response::FuelCallResponse;

    use super::*;

    pub async fn initialize(contract: &OracleContract, owner: Address) -> FuelCallResponse<()> {
        contract.methods().initialize(owner).call().await.unwrap()
    }

    pub async fn get_price(contract: &OracleContract, asset_id: ContractId) -> Option<Price> {
        contract
            .methods()
            .get_price(asset_id)
            .call()
            .await
            .unwrap()
            .value
    }

    pub async fn set_price(
        contract: &OracleContract,
        asset_id: ContractId,
        new_price: u64,
    ) -> FuelCallResponse<()> {
        contract
            .methods()
            .set_price(asset_id, new_price)
            .call()
            .await
            .unwrap()
    }
}

pub mod test_helpers {
    use fuels::types::SizedAsciiString;

    use super::{abigen_bindings::token_contract_mod, *};

    pub struct DeployTokenConfig {
        pub name: String,
        pub symbol: String,
        pub decimals: u8,
        pub mint_amount: u64,
    }

    pub async fn init_wallet() -> WalletUnlocked {
        let mut wallets = launch_custom_provider_and_get_wallets(
            WalletsConfig::new(
                Some(1),             /* Single wallet */
                Some(1),             /* Single coin (UTXO) */
                Some(1_000_000_000), /* Amount per coin */
            ),
            None,
            None,
        )
        .await;
        wallets.pop().unwrap()
    }

    pub async fn get_oracle_contract_instance(wallet: &WalletUnlocked) -> OracleContract {
        let id = Contract::deploy(
            "./out/debug/oracle.bin",
            &wallet,
            TxParameters::default(),
            StorageConfiguration::default(),
        )
        .await
        .unwrap();

        OracleContract::new(id, wallet.clone())
    }

    pub async fn get_token_contract_instance(
        wallet: &WalletUnlocked,
        deploy_config: &DeployTokenConfig,
    ) -> TokenContract {
        let mut name = deploy_config.name.clone();
        let mut symbol = deploy_config.symbol.clone();
        let decimals = deploy_config.decimals;

        let mut rng = rand::thread_rng();
        let salt = rng.gen::<[u8; 32]>();

        let id = Contract::deploy_with_parameters(
            "./tests/token/token_contract.bin",
            &wallet,
            TxParameters::default(),
            StorageConfiguration::default(),
            Salt::from(salt),
        )
        .await
        .unwrap();

        let instance = TokenContract::new(id, wallet.clone());
        let methods = instance.methods();

        let mint_amount = parse_units(deploy_config.mint_amount, decimals);
        name.push_str(" ".repeat(32 - deploy_config.name.len()).as_str());
        symbol.push_str(" ".repeat(8 - deploy_config.symbol.len()).as_str());

        let config: token_contract_mod::Config = token_contract_mod::Config {
            name: SizedAsciiString::<32>::new(name).unwrap(),
            symbol: SizedAsciiString::<8>::new(symbol).unwrap(),
            decimals,
        };

        let _res = methods
            .initialize(config, mint_amount, Address::from(wallet.address()))
            .call()
            .await;
        let _res = methods.mint().append_variable_outputs(1).call().await;

        instance
    }
}
```

### Main tests


Now, using the utils we can add some tests. Create folder `local_tests`, with files `mod.rs` and `set_price.rs`. In `mod.rs` add
```
pub mod set_price;
```

If you want to add more test files for local testing, you can create them in the same folder (`local_tests`) and add the filename to `mod.rs`. 

Whether the prices can be set can be tested as follows:
```rust
use crate::utils::local_test_utils::abi_calls::{get_price, initialize, set_price};
use crate::utils::local_test_utils::test_helpers::{
    get_oracle_contract_instance, get_token_contract_instance, init_wallet,
};
use crate::utils::local_test_utils::parse_units;
use fuels::tx::{Address, ContractId};

use crate::utils::{local_test_utils::test_helpers::DeployTokenConfig};
mod success {

    use super::*;

    #[tokio::test]
    async fn can_set_price() {
        let wallet = init_wallet().await;
        let oracle = get_oracle_contract_instance(&wallet).await;

        let config = DeployTokenConfig {
            name: String::from("BNB"),
            symbol: String::from("BNB"),
            decimals: 8,
            mint_amount: 5,
        };

        let bnb = get_token_contract_instance(&wallet, &config).await;
        let asset_id = ContractId::from(bnb.contract_id());

        initialize(&oracle, Address::from(wallet.address())).await;

        let set_price_amount: u64 = parse_units(250, config.decimals);
        set_price(&oracle, asset_id, set_price_amount).await;

        let price = get_price(&oracle, asset_id).await.unwrap().price;
        println!("{}", price);
        assert_eq!(price, set_price_amount);
    }
}
```

Run the test with `cargo test` or the Run button in the file. 