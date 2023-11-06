module MyAddr::mint_ticket {
    use std::option;
    use std::signer;
    use std::string::{Self, String};
    use aptos_framework::object::{Self, Object};
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;

    const ENOT_ADMIN: u64 = 1;
    const ENOT_OWNER: u64 = 2;
    const ENOT_EVENT_MANGER: u64 = 3;

    const EVENT_COLLECTION_NAME: vector<u8> = b"Event Collection Name";
    const EVENT_COLLECTION_DESCRIPTION: vector<u8> = b"event Collection Description";
    const EVENT_COLLECTION_URI: vector<u8> = b"https://event.collection.uri";

    /// Published under the contract owner's account.
    struct Config has key {
        /// Whitelist of event managers.
        whitelist: SmartVector<address>,
        /// `extend_ref` of the event collection manager object. Used to obtain its signer.
        extend_ref: object::ExtendRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Event token
    struct EventToken has key {
        /// Used to get the signer of the token
        extend_ref: object::ExtendRef,
        /// ticket collection name
        ticket_collection_name: String,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Ticket token
    struct TicketToken has key {
        /// Belonging event
        event: Object<EventToken>,
        price:u64
    }

    /// Initializes the module, creating the manager object, the event token collection and the whitelist.
    fun init_module(sender: &signer) acquires Config {
        // Create the event collection manager object to use it to autonomously
        // manage the event collection (e.g., create the collection and mint tokens).
        let constructor_ref = object::create_object(signer::address_of(sender));
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Publish the config resource.
        move_to(sender, Config { whitelist: smart_vector::new(), extend_ref});

        // Create the event collection.
        create_event_collection(&event_collection_manager_signer());
    }

    #[view]
    /// Returns the event token address by name
    public fun event_token_address(event_token_name: String): address acquires Config {
        token::create_token_address(&event_collection_manager_address(), &string::utf8(EVENT_COLLECTION_NAME), &event_token_name)
    }

    #[view]
    /// Returns the ticket token address by name
    public fun ticket_token_address(event_token: Object<EventToken>, ticket_token_name: String): address acquires EventToken {
        let event_token_addr = object::object_address(&event_token);
        let ticket_collection_name = &borrow_global<EventToken>(event_token_addr).ticket_collection_name;
        token::create_token_address(&event_token_addr, ticket_collection_name, &ticket_token_name)
    }

    /// Adds an event manager to the whitelist. This function allows the admin to add an event manager
    /// to the whitelist.
    public entry fun whitelist_event_manager(admin: &signer, event_manager: address) acquires Config {
        assert!(signer::address_of(admin) == event_collection_manager_owner(), ENOT_ADMIN);
        let config = borrow_global_mut<Config>(@MyAddr);
        smart_vector::push_back(&mut config.whitelist, event_manager);
    }

    /// Mints a event token, and creates a new associated ticket collection.
    /// This function allows a whitelisted event manager to mint a new event token.
    public entry fun mint_event(
        event_manager: &signer,
        description: String,
        name: String,
        uri: String,
        ticket_collection_name: String,
        ticket_collection_description: String,
        ticket_collection_uri: String,
    ) acquires Config {
        // Checks if the event manager is whitelisted.
        let event_manager_addr = signer::address_of(event_manager);
        assert!(is_whitelisted(event_manager_addr), ENOT_EVENT_MANGER);

        let collection = string::utf8(EVENT_COLLECTION_NAME);
        // Creates the event token, and get the constructor ref of the token. The constructor ref
        // is used to generate the refs of the token.
        let constructor_ref = token::create_named_token(
            &event_collection_manager_signer(),
            collection,
            description,
            name,
            option::none(),
            uri,
        );

        // Generates the object signer and the refs. The refs are used to manage the token.
        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Transfers the token to the guild master.
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, event_manager_addr);


        // Publishes the EventToken resource with the refs.
        let event_token = EventToken {
            extend_ref,
            ticket_collection_name,
        };
        move_to(&object_signer, event_token);

        // Creates a ticket collection which is associated to the event token.
        create_ticket_collection(&object_signer, ticket_collection_name, ticket_collection_description, ticket_collection_uri);
    }

    /// Mints a ticket token. This function mints a new ticket token and transfers it to the
    /// `receiver` address.
    public entry fun mint_ticket(
        event_manager: &signer,
        event_token: Object<EventToken>,
        description: String,
        name: String,
        uri: String,
        receiver: address,
        price: u64
    ) acquires EventToken {
        // Checks if the event manager is the owner of the event token.
        assert!(object::owner(event_token) == signer::address_of(event_manager), ENOT_OWNER);

        let event = borrow_global<EventToken>(object::object_address(&event_token));
        let event_token_object_signer = object::generate_signer_for_extending(&event.extend_ref);
        // Creates the ticket token, and get the constructor ref of the token. The constructor ref
        // is used to generate the refs of the token.
        let constructor_ref = token::create_named_token(
            &event_token_object_signer,
            event.ticket_collection_name,
            description,
            name,
            option::none(),
            uri,
        );

        // Generates the object signer and the refs. The refs are used to manage the token.
        let object_signer = object::generate_signer(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);

        // Transfers the token to the `soul_bound_to` address
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        // Publishes the TicketToken resource with the refs.
        let ticket_token = TicketToken {
            event: event_token,
            price,
        };
        move_to(&object_signer, ticket_token);
    }

    /// Returns the signer of the event collection manager object.
    fun event_collection_manager_signer(): signer acquires Config {
        let manager = borrow_global<Config>(@MyAddr);
        object::generate_signer_for_extending(&manager.extend_ref)
    }

    /// Returns the signer of the event collection manager object.
    fun event_collection_manager_owner(): address acquires Config {
        let manager = borrow_global<Config>(@MyAddr);
        let manager_addr = object::address_from_extend_ref(&manager.extend_ref);
        object::owner(object::address_to_object<object::ObjectCore>(manager_addr))
    }

    /// Returns the address of the event collection manager object.
    fun event_collection_manager_address(): address acquires Config {
        let manager = borrow_global<Config>(@MyAddr);
        object::address_from_extend_ref(&manager.extend_ref)
    }

    /// Creates the event collection. This function creates a collection with unlimited supply using
    /// the module constants for description, name, and URI, defined above. The royalty configuration
    /// is skipped in this collection for simplicity.
    fun create_event_collection(admin: &signer) {
        // Constructs the strings from the bytes.
        let description = string::utf8(EVENT_COLLECTION_DESCRIPTION);
        let name = string::utf8(EVENT_COLLECTION_NAME);
        let uri = string::utf8(EVENT_COLLECTION_URI);

        // Creates the collection with unlimited supply and without establishing any royalty configuration.
        collection::create_unlimited_collection(
            admin,
            description,
            name,
            option::none(),
            uri,
        );
    }

    /// Creates the ticket collection. This function creates a collection with unlimited supply using
    /// the module constants for description, name, and URI, defined above. The royalty configuration
    /// is skipped in this collection for simplicity.
    fun create_ticket_collection(event_token_object_signer: &signer, name: String, description: String, uri: String) {
        // Creates the collection with unlimited supply and without establishing any royalty configuration.
        collection::create_unlimited_collection(
            event_token_object_signer,
            description,
            name,
            option::none(),
            uri,
        );
    }

    public fun is_whitelisted(event_manager: address): bool acquires Config {
        let whitelist = &borrow_global<Config>(@MyAddr).whitelist;
        smart_vector::contains(whitelist, &event_manager)
    }

    #[test(fx = @std, admin = @MyAddr, event_manager = @0x456, user = @0x789)]
    public fun test_guild(fx: signer, admin: &signer, event_manager: &signer, user: address) acquires EventToken, Config {
        use std::features;

        let feature = features::get_auids();
        features::change_feature_flags(&fx, vector[feature], vector[]);

        // This test assumes that the creator's address is equal to @token_objects.
        assert!(signer::address_of(admin) == @MyAddr, 0);

        // -----------------------------------
        // Admin creates the event collection.
        // -----------------------------------
        init_module(admin);

        // ---------------------------------------------
        // Admin adds the event manager to the whitelist.
        // ---------------------------------------------
        whitelist_event_manager(admin, signer::address_of(event_manager));

        // ------------------------------------------
        // event manager mints an event token.
        // ------------------------------------------
        mint_event(
            event_manager,
            string::utf8(b"Guild Token #1 Description"),
            string::utf8(b"Guild Token #1"),
            string::utf8(b"Guild Token #1 URI"),
            string::utf8(b"Member Collection #1"),
            string::utf8(b"Member Collection #1 Description"),
            string::utf8(b"Member Collection #1 URI"),
        );

        // -------------------------------------------
        // EventManager mints a ticket token for User.
        // -------------------------------------------
        let token_name = string::utf8(b"Member Token #1");
        let token_description = string::utf8(b"Member Token #1 Description");
        let token_uri = string::utf8(b"Member Token #1 URI");
        let event_token_addr = event_token_address(string::utf8(b"Guild Token #1"));
        let event_token = object::address_to_object<EventToken>(event_token_addr);
        // Creates the member token for User.
        mint_ticket(
            event_manager,
            event_token,
            token_description,
            token_name,
            token_uri,
            user,
            10000
        );

    }
}