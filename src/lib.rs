extern crate alloc;

// Modules and imports
mod erc721;

/// Import the Stylus SDK along with alloy primitive types for use in our program.
use stylus_sdk::{
    abi::Bytes,
    call::Call,
    contract,
    msg,
    prelude::*,
    alloy_primitives::{Address, uint, U256}
};
use alloy_sol_types::sol;
use crate::erc721::{Erc721, Erc721Params};

// Interfaces for the Art contract and the ERC20 contract
sol_interface! {
    interface NftArt {
        function initialize(address token_contract_address) external;
        function generateArt(uint256 token_id, address owner) external returns(string);
    }
}

struct StylusNFTParams;

/// Immutable definitions
impl Erc721Params for StylusNFTParams {
    const NAME: &'static str = "StylusNFT";
    const SYMBOL: &'static str = "SNFT";
}

// Define the entrypoint as a Solidity storage object. The sol_storage! macro
// will generate Rust-equivalent structs with all fields mapped to Solidity-equivalent
// storage slots and types.
sol_storage! {
    #[entrypoint]
    struct StylusNFT {
        address art_contract_address;

        #[borrow] // Allows erc721 to access MyToken's storage and make calls
        Erc721<StylusNFTParams> erc721;
    }
}

// Declare Solidity error types
sol! {
    /// Contract has already been initialized
    error AlreadyInitialized();
    /// A call to an external contract failed
    error ExternalCallFailed();
}

/// Represents the ways methods may fail.
#[derive(SolidityError)]
pub enum StylusNFTError {
    AlreadyInitialized(AlreadyInitialized),
    ExternalCallFailed(ExternalCallFailed),
}

#[public]
#[inherit(Erc721<StylusNFTParams>)]
impl StylusNFT {
    /// Mints an NFT, but does not call onErc712Received
    pub fn mint(&mut self) -> Result<(), Vec<u8>> {
        let minter = msg::sender();
        self.erc721.mint(minter)?;
        Ok(())
    }

    /// Mints an NFT to the specified address, and does not call onErc712Received
    pub fn mint_to(&mut self, to: Address) -> Result<(), Vec<u8>> {
        self.erc721.mint(to)?;
        Ok(())
    }

    /// Mints an NFT and calls onErc712Received with empty data
    pub fn safe_mint(&mut self, to: Address) -> Result<(), Vec<u8>> {
        Erc721::safe_mint(self, to, Vec::new())?;
        Ok(())
    }

    /// Mints an NFT and calls onErc712Received with the specified data
    #[selector(name = "safeMint")]
    pub fn safe_mint_with_data(&mut self, data: Bytes) -> Result<(), Vec<u8>> {
        let minter = msg::sender();
        Erc721::safe_mint(self, minter, data.0)?;
        Ok(())
    }

    /// Burns an NFT
    pub fn burn(&mut self, token_id: U256) -> Result<(), Vec<u8>> {
        // This function checks that msg::sender() owns the specified token_id
        self.erc721.burn(msg::sender(), token_id)?;
        Ok(())
    }

    /// Returns the image for the NFT
    #[selector(name = "tokenURI")]
    pub fn token_uri(&mut self, token_id: U256) -> Result<String, Vec<u8>> {
        let owner = self.erc721.owner_of(token_id)?;
        let art_contract_address = self.art_contract_address.get();
        let art_contract = NftArt::new(art_contract_address);
        let config = Call::new();
        let image = art_contract
            .generate_art(config, token_id, owner)
            .map_err(|_e| StylusNFTError::ExternalCallFailed(ExternalCallFailed {}))?;

        Ok(image)
    }

    /// Initialize program - simplified version without ERC20
    pub fn initialize(&mut self, art_contract_address: Address) -> Result<(), StylusNFTError> {
        let current_art_contract = self.art_contract_address.get();
        if !current_art_contract.is_zero() {
            return Err(StylusNFTError::AlreadyInitialized(AlreadyInitialized {}));
        }
        self.art_contract_address.set(art_contract_address);

        // Initializing the Art contract
        let art_contract = NftArt::new(art_contract_address);
        let config = Call::new();
        let _result = art_contract
            .initialize(config, contract::address())
            .map_err(|_e| StylusNFTError::ExternalCallFailed(ExternalCallFailed {}))?;

        Ok(())
    }

    /// Getter for the art contract address
    pub fn get_art_contract_address(&mut self) -> Result<Address, StylusNFTError> {
        Ok(self.art_contract_address.get())
    }
}
