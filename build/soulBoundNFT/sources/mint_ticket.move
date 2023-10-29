module MyAddr::mint_ticket{
    use std::option;
    use std::string::{Self, String};
    use std::signer;
    use std::debug;

    use aptos_framework::object::{Self, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::token;

    use aptos_std::smart_vector::{Self, SmartVector};

    const ENOT_ADMIN: u64 = 1;
    const ENOT_EVENT_MANAGER: u64 = 2;
    const ENOT_OWNER: u64 = 3;

    struct Config has key {
        whitelist: SmartVector<address>, // Whitelisting event managers
        extend_ref: object::ExtendRef, /// `extend_ref` of the event manager object. Used to obtain its signer.
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    // Event Token
    struct EventToken has key {
        extend_ref: object::ExtendRef, 
        event_collection_name: String, 
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    // Ticket token
    struct TicketToken has key {
        event: Object<EventToken>, // Belonging to event
        transfer_ref: object::TransferRef,
    }

    fun init_module(sender: &signer) {
        // Create the event manager object to use it to autonomously
        // manage the collection (e.g., create the collection and mint tokens).
        let constructor_ref = object::create_object(signer::address_of(sender));
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Publish the config resource.
        move_to(sender, Config { whitelist: smart_vector::new(), extend_ref});
    }

    // This function allows the admin to add an event manager to the whitelist.
    public entry fun whitelist_event_manager(admin: &signer, event_manager: address) acquires Config {
        assert!(signer::address_of(admin) == @MyAddr, ENOT_ADMIN);
        let config = borrow_global_mut<Config>(signer::address_of(admin));
        smart_vector::push_back(&mut config.whitelist, event_manager);
    }

    #[view]
    public fun is_whitelisted(event_manager: address): bool acquires Config{
        let whitelist = &borrow_global<Config>(@MyAddr).whitelist;
        smart_vector::contains(whitelist, &event_manager)
    }

    fun event_manager_signer(): signer acquires Config {
        let manager = borrow_global<Config>(@MyAddr);
        object::generate_signer_for_extending(&manager.extend_ref)
    }

    public entry fun mint_event(
        event_manager: &signer,
        collection: String,
        description: String,
        max_supply: u64,
        name: String,
        uri: String,
        event_collection_name: String,
        event_collection_description: String,
        event_collection_uri: String,
    ) acquires Config {
        let event_manager_address = signer::address_of(event_manager);
        assert!(is_whitelisted(event_manager_address), ENOT_EVENT_MANAGER);

        let constructor_ref = token::create_named_token(
            &event_manager_signer(),
            collection,
            description,
            name,
            option::none(),
            uri,
        );

        // Generates the object signer and the refs. The refs are used to manage the token.
        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Transfers the token to the event.
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, event_manager_address);


        // Publishes the EventManagerToken resource with the refs.
        let event_token = EventToken {
            extend_ref,
            event_collection_name,
        };
        move_to(&object_signer, event_token);

        // Creates an event collection which is associated to the  EventToken.
        create_event_collection(&object_signer, event_collection_name, event_collection_description, event_collection_uri, max_supply);
    }

    fun create_event_collection(event_token_object_signer: &signer, name: String, description: String, uri: String, max_supply: u64) {
        // Creates the collection with unlimited supply and without establishing any royalty configuration.
        collection::create_fixed_collection(
            event_token_object_signer,
            description,
            max_supply,
            name,
            option::none(),
            uri,
        );
    }

    // This function mints a new Event token and transfers it to the `receiver` address.
    public entry fun mint_ticket(
        event_manager: &signer,
        event_token: Object<EventToken>,
        description: String,
        name: String,
        uri: String,
        receiver: address,
    ) acquires EventToken {
        // Checks if the event manager is the owner of the event token.
        assert!(object::owner(event_token) == signer::address_of(event_manager), ENOT_OWNER);

        let event = borrow_global<EventToken>(object::object_address(&event_token));
        let event_token_object_signer = object::generate_signer_for_extending(&event.extend_ref);
        // Creates the member token, and get the constructor ref of the token. The constructor ref
        // is used to generate the refs of the token.
        let constructor_ref = token::create_named_token(
            &event_token_object_signer,
            event.event_collection_name,
            description,
            name,
            option::none(),
            uri,
        );

        // Generates the object signer and the refs. The refs are used to manage the token.
        let object_signer = object::generate_signer(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);

        // Transfers the token to the `soul_bound_to` address
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);
        object::disable_ungated_transfer(&transfer_ref);

        // Publishes the TicketToken resource with the refs.
        let ticket_token = TicketToken {
            event: event_token,
            transfer_ref
        };
        move_to(&object_signer, ticket_token);
    }

    fun event_collection_manager_address(): address acquires Config {
        let manager = borrow_global<Config>(@MyAddr);
        object::address_from_extend_ref(&manager.extend_ref)
    }

     public fun event_token_address(event_token_name: String, collection: String): address acquires Config {
        token::create_token_address(&event_collection_manager_address(), &collection, &event_token_name)
    }



    #[test(admin = @MyAddr, event_manager = @0x456, fx = @std, user = @0x789)]
    public entry fun test_whitelisted(fx: signer, admin: &signer, event_manager: &signer, user: address) acquires Config, EventToken{
        use std::features;

        let feature = features::get_auids();
        features::change_feature_flags(&fx, vector[feature], vector[]);

        assert!(signer::address_of(admin) == @MyAddr, ENOT_ADMIN);
        init_module(admin);
        whitelist_event_manager(admin, signer::address_of(event_manager));
        let whitelisted = is_whitelisted(signer::address_of(event_manager));
        debug::print<bool>(&whitelisted);

        mint_event(
            event_manager,
            string::utf8(b"Guild Token #1 Collection"),
            string::utf8(b"Guild Token #1 Description"),
            10000,
            string::utf8(b"Guild Token #1"),
            string::utf8(b"Guild Token #1 URI"),
            string::utf8(b"Member Collection #1"),
            string::utf8(b"Member Collection #1 Description"),
            string::utf8(b"Member Collection #1 URI"),
        );

        let token_name = string::utf8(b"Member Token #1");
        let token_description = string::utf8(b"Member Token #1 Description");
        let token_uri = string::utf8(b"Member Token #1 URI");
        let guild_token_addr = event_token_address(string::utf8(b"Guild Token #1"), string::utf8(b"Guild Token #1 Collection"));
        let guild_token = object::address_to_object<EventToken>(guild_token_addr);

        mint_ticket(
            event_manager,
            guild_token,
            token_description,
            token_name,
            token_uri,
            user,
        );
    }

}