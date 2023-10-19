module MyAddr::mint_ticket{
    use std::bcs;
    use std::error;
    use std::signer;
    use std::string::{Self,String};
    use std::vector;

    use aptos_token::token;
    use aptos_token::token::TokenDataId;

    use aptos_framework::account::SignerCapability;
    use aptos_framework::resource_account;
    use aptos_framework::account;
    use aptos_framework::timestamp;

    use aptos_std::ed25519;

    /* TokenDataId is a struct:
    struct TokenDataId has copy, drop, store {
        creator: address, --> The address of the creator, eg: 0xcafe
        collection: String, --> The name of collection; this is unique under the same account, eg: "Taylor Swift Concert"
        name: String, -->  The name of the token; this is the same as the name field of TokenData
    }*/
    struct TicketMintingEvent has drop, store {
        ticket_receiver_address: address,
        ticket_data_id: TokenDataId,
    }

    struct TicketData has key {
        signer_cap: SignerCapability,
        ticket_data_id: TokenDataId,
        expiration_timestamp: u64,
        minting_enabled: bool,
    }

    const ENOT_AUTHORIZED:u64 = 1;
    const ECOLLECTION_EXPIRED: u64 = 2;
    const EMINTING_DISABLED: u64 = 3;

    fun init_module(resource_owner: &signer){
        let collection_name = string::utf8(b"Event name");
        let description = string::utf8(b"Event description");
        let collection_uri = string::utf8(b"Collection uri");
        let maximum_supply = 900;
        let mutate_setting = vector<bool>[ false, false, false ]; // mutate settings for ddescription, uri and maximum supply

        token::create_collection(resource_owner, collection_name, description, collection_uri, maximum_supply, mutate_setting);

        let token_name = string::utf8(b"Event token name");
        let token_uri = string::utf8(b"Event token uri");

        let ticket_data_id = token::create_tokendata(
            resource_owner, // account
            collection_name, //collection name
            token_name, // token name
            string::utf8(b""), // description
            maximum_supply, // maximum
            token_uri,
            signer::address_of(resource_owner), // royalty_payee_address
            1, // royalty_points_denominator
            0, // royalty_points_numerator
            token::create_token_mutability_config(
                &vector<bool>[ false, false, false, false, true ]
            ), // token_mutate_config -> tokenMaximum, uri, royalt, description, property map.
            vector<String>[string::utf8(b"given_to")], // property_keys
            vector<vector<u8>>[b""], // property_values
            vector<String>[ string::utf8(b"address") ], // property_types
        );

        let resource_owner_signer_cap = resource_account::retrieve_resource_account_cap(resource_owner, @MyAddr);

        move_to(resource_owner, TicketData {
            signer_cap: resource_owner_signer_cap, 
            ticket_data_id, 
            minting_enabled: false, 
            expiration_timestamp: 10000000000});
    }

    public entry fun mint_ticket(receiver: &signer) acquires TicketData{
        let ticket_data = borrow_global_mut<TicketData>(@MyAddr);

        assert!(timestamp::now_seconds() < ticket_data.expiration_timestamp, error::permission_denied(ECOLLECTION_EXPIRED));
        assert!(ticket_data.minting_enabled, error::permission_denied(EMINTING_DISABLED));

        let resource_signer = account::create_signer_with_capability(&ticket_data.signer_cap);
        let ticket_id = token::mint_token(&resource_signer, ticket_data.ticket_data_id, 1); // creator, tokenDataId, how many to mint;
        token::direct_transfer(&resource_signer, receiver, ticket_id, 1); // sender, receiver, tokenId, how many transfers to the receiver;
        let (creator_address, collection, name) = token::get_token_data_id_fields(&ticket_data.ticket_data_id);

        token::mutate_token_properties(
            &resource_signer, // owner
            signer::address_of(receiver), // token_owner
            creator_address, // creator
            collection, // collection name
            name, // token name
            0, // token_property_version
            1, // how many
            vector::empty<String>(), // property map key
            vector::empty<vector<u8>>(), // property map values
            vector::empty<String>(), // property map types
        );
    }

    public entry fun set_minting_enabled(caller: &signer, minting_enabled: bool) acquires TicketData {
        let caller_address = signer::address_of(caller);
        assert!(caller_address == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        let ticket_data = borrow_global_mut<TicketData>(@MyAddr);
        ticket_data.minting_enabled = minting_enabled;
    }

    public entry fun set_timestamp(caller: &signer, expiration_timestamp: u64) acquires TicketData {
        let caller_address = signer::address_of(caller);
        assert!(caller_address == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        let ticket_data = borrow_global_mut<TicketData>(@MyAddr);
        ticket_data.expiration_timestamp = expiration_timestamp;
    }

}