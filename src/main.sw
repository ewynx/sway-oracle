contract;

use std::{
  auth::{msg_sender, AuthError},
  block::timestamp,
  constants::ZERO_B256,
  result::Result,
  revert::require
};

struct Price {
  asset_id: ContractId,
  price: u64,
  last_update: u64
}

storage {
  owner: Address = Address::from(ZERO_B256),
  prices: StorageMap<ContractId, Price> = StorageMap {},
}

enum Error {
  OwnerAlreadyInitialized: (),
  AccessDenied: ()
}

abi Oracle {
    #[storage(read)]
    fn owner() -> Identity;

    #[storage(read, write)]
    fn initialize(owner: Address);

    #[storage(read, write)]
    fn set_price(asset_id: ContractId, price_value: u64);

    #[storage(read, write)]
    fn set_prices(prices: Vec<(ContractId, u64)>);

    #[storage(read)]
    fn get_price(asset_id: ContractId) -> Option<Price>;
} 

fn get_msg_sender_or_panic() -> Address {
  let sender: Result<Identity, AuthError> = msg_sender();
  if let Identity::Address(address) = sender.unwrap() {
    address
  } else {
    revert(0)
  }
}

#[storage(read)]
fn owner_check() {
  let sender = get_msg_sender_or_panic();
  require(sender == storage.owner, Error::AccessDenied);
}

impl Oracle for Contract {
    #[storage(read)]
    fn owner() -> Identity {
      Identity::Address(storage.owner)
    }

    #[storage(read, write)]
    fn initialize(owner: Address) {
      require(storage.owner == Address::from(ZERO_B256), Error::OwnerAlreadyInitialized);
      storage.owner = owner;
    }

    #[storage(read, write)]
    fn set_price(asset_id: ContractId, price_value: u64) {
      owner_check();
      let price = Price {
        asset_id: asset_id,
        price: price_value,
        last_update: timestamp(),
      };
      storage.prices.insert(asset_id, price);
    }

    #[storage(read, write)]
    fn set_prices(prices: Vec<(ContractId, u64)>) {
      owner_check();
      let len = prices.len();
      let mut i = 0;
      while i < len {
        if let Option::Some(price) = prices.get(i) {
          let price_struct = Price {
            asset_id: price.0,
            price: price.1,
            last_update: timestamp(),
          };
          storage.prices.insert(price.0, price_struct);
        }
        i += 1;
      }
    }

    #[storage(read)]
    fn get_price(asset_id: ContractId) -> Option<Price> {
      storage.prices.get(asset_id)
    }
}
