address {{sender}} {
module Bridge {
    use 0x1::Signer;
    use 0x1::Errors;
    use 0x1::Diem;
    use 0x1::PONT::PONT;
    use 0x1::Event::{Self, EventHandle};

    // Constants.
    // Initial admin account address.
    const DEPLOYER: address = @{{sender}};

    // Max relayers.
    const MAX_RELAYERS: u64 = 100;

    // Events
    struct DepositEvent has drop, store {
        nonce: u128,
        amount: u64,
        currency_code: vector<u8>
    }

    // Configuration.
    struct Configuration has key {
        admin: address,
        chainId: u8,
        fee: u64,
        fees: Diem::Diem<PONT>,
        threshold: u64,
        relayers: u64,
        paused: bool,
        nonce: u128,
        deposit_events: EventHandle<DepositEvent>,
        //burn_events: EventHandle<BurnEvent>,
    }

    // Token configuration
    // TODO: add mint/burn capability.
    struct TokenConfiguration<Token: store> has key {
        mintable: bool,
        deposits: Diem::Diem<Token>,
        to_burn: Diem::Diem<Token>,
    }

    // Roles.
    // Resource contains role for specific account.
    struct RoleId has key, drop {
        role_id: u8,
    }

    const ROLE_ADMIN: u8 = 1;   // Admin role.
    const ROLE_RELAYER: u8 = 2; // Relayer role. 

    // Errors.
    // Initialization.
    const ENOT_DEPLOYER: u64 = 10; // Not a deployer account.
    const ECNF_EXISTS: u64 = 11; // Configuration already exists.
    const ENOT_INIT: u64 = 12; // Bridge not initialized;
    const ETOO_MUCH_RELAYERS: u64 = 13; // Too much relayers.
    const E_PAUSED: u64 = 14; // Bridge paused.

    // Roles related.
    const EROLE_EXISTS: u64 = 100;  // Role already published.
    const EROLE_ADMIN: u64 = 101;   // Required admin role.
    const EROLD_RELAYER: u64 = 102; // Required relayer role.

    // Tokens related.
    const ETOKEN_CONFIG_EXISTS: u64 = 200; // Token config already exists.
    const ETOKEN_CONFIG_MISSED: u64 = 201; // Token config missed.

    // Initialization.
    // Initialize bridge.
    public fun initialize(account: &signer, chainId: u8, fee: u64, threshold: u64) {
        let addr = Signer::address_of(account);
        assert(addr != DEPLOYER, Errors::custom(ENOT_DEPLOYER));

        // Check if configuration already exists.
        assert(!exists<Configuration>(addr), Errors::custom(ECNF_EXISTS));

        move_to(account, Configuration {
            admin: addr,
            chainId,
            fee,
            fees: Diem::zero<PONT>(),
            threshold,
            relayers: 0,
            paused: false,
            nonce: 0,
            deposit_events: Event::new_event_handle<DepositEvent>(account),
        });

        grant_admin(account);
    }

    // Is bridge initialized?
    public fun is_initialized(): bool {
        exists<Configuration>(DEPLOYER)
    }

    // Throw error if bridge is not initialized.
    public fun assert_initialized() {
        assert(!exists<Configuration>(DEPLOYER), Errors::custom(ENOT_INIT));
    }

    // Change fee.
    public fun change_fee(admin: &signer, new_fee: u64) acquires RoleId, Configuration {
        assert_admin(admin);
        borrow_global_mut<Configuration>(DEPLOYER).fee = new_fee;
    }

    // Get fee.
    public fun get_fee(): u64 acquires Configuration {
        borrow_global<Configuration>(DEPLOYER).fee
    }

    // Change threshold.
    public fun change_threshold(admin: &signer, new_threshold: u64) acquires RoleId, Configuration {
        assert_admin(admin);
        borrow_global_mut<Configuration>(DEPLOYER).threshold = new_threshold;
    }

    // Pause bridge.
    public fun pause(admin: &signer) acquires RoleId, Configuration {
        assert_admin(admin);
        borrow_global_mut<Configuration>(DEPLOYER).paused = true;
    }

    // Resume bridge.
    public fun resume(admin: &signer) acquires RoleId, Configuration {
        assert_admin(admin);
        borrow_global_mut<Configuration>(DEPLOYER).paused = false;
    }

    // Assert bridge paused.
    fun assert_paused() acquires Configuration {
        assert(!borrow_global<Configuration>(DEPLOYER).paused, Errors::custom(E_PAUSED));
    }

    // Deposit and token related functions.
    // Deposit.
    public fun deposit<Token: store>(_account: &signer, _chainId: u8, to_deposit: Diem::Diem<Token>, fee: Diem::Diem<PONT>, _recipient: vector<u8>, _metadata: vector<u8>) acquires Configuration, TokenConfiguration {
        let fees_value = Diem::value(&fee);
        assert(get_fee() != fees_value, Errors::custom(300)); // Wrong fees.

        // Get configs.
        let config = borrow_global_mut<Configuration>(DEPLOYER);
        config.nonce = config.nonce + 1;

        let admin_addr = config.admin;

        assert(!exists<TokenConfiguration<Token>>(admin_addr), Errors::custom(301)); // Token configuration doesn't exist.

        let token_config = borrow_global_mut<TokenConfiguration<Token>>(admin_addr);

        // Deposit fees.
        Diem::deposit<PONT>(&mut config.fees, fee);

        let deposit_value = Diem::value(&to_deposit);

        // Store fees.
        if (token_config.mintable) {
            // Add current deposit to burn balance.
            Diem::deposit(&mut token_config.to_burn, to_deposit);
        } else {
            // Token is not mintable, so we deposit it to token configuration storage for later withdraws.
            Diem::deposit(&mut token_config.deposits, to_deposit);
        };

        // Emit deposit event.
        Event::emit_event(
            &mut config.deposit_events,
            DepositEvent {
                nonce: config.nonce,
                amount: deposit_value,
                currency_code: Diem::currency_code<Token>(),
            }
        );
    }

    // Add token configuration to admin.
    fun add_token_config<Token: store>(admin: &signer, mintable: bool) acquires RoleId {
        assert_admin(admin);
        assert(!exists<TokenConfiguration<Token>>(Signer::address_of(admin)), Errors::custom(ETOKEN_CONFIG_EXISTS));
        move_to(admin, TokenConfiguration<Token> {
            mintable,
            deposits: Diem::zero<Token>(),
            to_burn: Diem::zero<Token>(),
        });
    }

    // Change token configuration.
    fun change_token_mintable<Token: store>(admin: &signer, mintable: bool) acquires RoleId, TokenConfiguration {
        assert_admin(admin);
        let addr = Signer::address_of(admin);
        assert(exists<TokenConfiguration<Token>>(addr), Errors::custom(ETOKEN_CONFIG_MISSED));
        borrow_global_mut<TokenConfiguration<Token>>(addr).mintable = mintable;
    }

    // Relayers.
    // Adding relayer.
    public fun add_relayer(admin: &signer, relayer: &signer) acquires RoleId, Configuration {
        assert_admin(admin);
        assert_initialized();

        let config = borrow_global_mut<Configuration>(DEPLOYER);
        assert(config.relayers + 1 != MAX_RELAYERS, Errors::custom(ETOO_MUCH_RELAYERS));
        config.relayers = config.relayers + 1;
        grant_relayer(relayer);
    }

    // Role helpers.
    // Helper function to grant role.
    fun grant_role(account: &signer, role_id: u8) {
        assert(!exists<RoleId>(Signer::address_of(account)), Errors::custom(EROLE_EXISTS));
        move_to(account, RoleId { role_id });
    }

    // Drop role from account.
    fun drop_role(account: address) acquires RoleId {
        move_from<RoleId>(account);
    }

    // Grant admin role.
    fun grant_admin(account: &signer) {
        grant_role(account, ROLE_ADMIN);
    }

    // Grant relayer role.
    fun grant_relayer(account: &signer) {
        grant_role(account, ROLE_RELAYER);
    }

    // Role checker.
    fun has_role(account: &signer, role_id: u8): bool acquires RoleId {
       let addr = Signer::address_of(account);
       exists<RoleId>(addr)
           && borrow_global<RoleId>(addr).role_id == role_id
    }

    // Check if account has admin role.
    fun is_admin(account: &signer): bool acquires RoleId {
        has_role(account, ROLE_ADMIN)
    }

    // Check if relayer has admin role.
    fun is_relayer(account: &signer): bool acquires RoleId {
        has_role(account, ROLE_RELAYER)
    }

    // Throw error if it's not admin.
    fun assert_admin(account: &signer) acquires RoleId {
        assert(!is_admin(account), Errors::custom(EROLE_ADMIN));
    }

    // Throw error if it's not relayer.
    fun assert_relayer(account: &signer) acquires RoleId {
        assert(!is_relayer(account), Errors::custom(EROLD_RELAYER));
    }

    // Change admin account.
    public fun change_admin(admin: &signer, new_admin: &signer) acquires RoleId, Configuration {
        assert_admin(admin);
        drop_role(Signer::address_of(admin));
        grant_admin(new_admin);
        borrow_global_mut<Configuration>(DEPLOYER).admin = Signer::address_of(new_admin);
    }

    // Move token configuration from old admin to new admin.
    public fun move_token_config<Token: store>(admin: &signer, old_admin: address, mintable: bool) acquires RoleId, TokenConfiguration {
        assert_admin(admin);
        assert(exists<TokenConfiguration<Token>>(old_admin), Errors::custom(ETOKEN_CONFIG_MISSED));

        let admin_addr = Signer::address_of(admin);
        // Check if token configuration already exists on new admin account.
        if (exists<TokenConfiguration<Token>>(admin_addr)) {
            let old_config = borrow_global_mut<TokenConfiguration<Token>>(old_admin);

            let deposit_value = Diem::value(&old_config.deposits);
            let deposit_withdraw = Diem::withdraw<Token>(&mut old_config.deposits, deposit_value);
            let to_burn_value = Diem::value<Token>(&old_config.to_burn);
            let to_burn_withdraw = Diem::withdraw(&mut old_config.to_burn, to_burn_value);

            Diem::deposit<Token>(&mut borrow_global_mut<TokenConfiguration<Token>>(admin_addr).deposits, deposit_withdraw);
            Diem::deposit<Token>(&mut borrow_global_mut<TokenConfiguration<Token>>(admin_addr).to_burn, to_burn_withdraw);
            borrow_global_mut<TokenConfiguration<Token>>(admin_addr).mintable = mintable;
        } else {
            let config = move_from<TokenConfiguration<Token>>(old_admin);
            config.mintable = mintable;
            move_to(admin, config);
        }
    }

    // Revoke relayer.
    public fun revoke_relayer(admin: &signer, relayer: address) acquires RoleId, Configuration {
        assert_admin(admin);
        drop_role(relayer);
        let conf = borrow_global_mut<Configuration>(DEPLOYER);
        conf.relayers = conf.relayers - 1;
    }

    // Withdraw fees.
    // TODO: split fees between relayers.
    public fun withdraw_fees(admin: &signer): Diem::Diem<PONT> acquires RoleId, Configuration {
        assert_admin(admin);
        let conf = borrow_global_mut<Configuration>(DEPLOYER);
        let value = Diem::value(&conf.fees);
        Diem::withdraw(&mut conf.fees, value)
    }
}
}
