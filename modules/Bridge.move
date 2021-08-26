address {{sender}} {
module Bridge {
    use 0x1::Signer;
    use 0x1::Errors;
    use 0x1::Diem::{Self, Diem};
    use 0x1::PONT::PONT;
    use 0x1::Event::{Self, EventHandle};
    use 0x1::DiemBlock;
    use 0x1::Vector;
    use 0x1::Option::{Self, Option};
    use 0x1::BCS;
    use 0x1::Hash;

    // Constants.
    // Initial admin account address.
    const DEPLOYER: address = @{{sender}};

    // Max relayers.
    const MAX_RELAYERS: u64 = 100;

    // Events
    // When new deposit happens.
    struct DepositEvent has drop, store {
        chainId: u8,
        nonce: u128,
        amount: u64,
        currency_code: vector<u8>,
        recipient: address,
        metadata: vector<u8>,
    }

    // Relay status events.
    const RELAY_STATUS_ADDED:   u64 = 0; 
    const RELAY_STATUS_REVOKED: u64 = 1;

    struct RelayersStatusEvent has drop, store {
        account: address,
        status: u64,
        count: u64,
    }

    // Configuration events: paused, threshold.
    struct ConfigEvent has drop, store {
        fee: u64,
        paused: bool,
        threshold: u64,
    }

    // Proposal created event.
    struct ProposalEvent has drop, store {
        relayer: address,
        id: u128,
        currency_code: vector<u8>,
        amount: u64,
        recipient: address,
        deadline: u64,
    }

    // Vote for proposal event.
    struct VoteEvent has drop, store {
        id: u128,
        relayer: address,
        yes: bool,
    }

    // Proposal status changed (passed/rejected).
    struct ProposalStatusEvent has drop, store {
        id: u128,
        status: u64
    }

    // Configuration.
    struct Configuration has key {
        admin: address, // Address of admin account.
        chainId: u8, // Id of current chain.
        fee: u64, // Fee amount in PONT.
        fees: Diem<PONT>, // Collecting PONT fees here.
        threshold: u64, // Current threshold.
        relayers: u64, // Current amount of relayers.
        paused: bool, // Is bridge paused.
        nonce: u128, // Current deposit nonce.
        deadline: u64, // Deadline for votes in blocks.

        // Events handlers.
        deposit_events: EventHandle<DepositEvent>,
        relayers_status_events: EventHandle<RelayersStatusEvent>,
        config_events: EventHandle<ConfigEvent>,
        proposal_events: EventHandle<ProposalEvent>,
        vote_events: EventHandle<VoteEvent>,
        proposal_status_events: EventHandle<ProposalStatusEvent>
    }

    // Token configuration.
    // TODO: add mint/burn capability.
    struct TokenConfiguration<Token: store + drop> has key {
        mintable: bool,
        deposits: Diem<Token>,
        to_burn: Diem<Token>,
    }

    // Proposal.
    const PROPOSAL_STATUS_VOTING: u64 = 0;
    const PROPOSAL_STATUS_REJECTED: u64 = 1;
    const PROPOSAL_STATUS_PASSED: u64 = 2;
    struct Proposal<Token: store + drop> has key, store, drop {
        id: u128,
        amount: u64,
        recipient: address,
        metadata: vector<u8>,
        deadline: u64,
        votes_yes: vector<address>,
        votes_no: vector<address>,
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
    const ECFG_NOT_DEPLOYER: u64 = 10; // Not a deployer account.
    const ECFG_EXISTS: u64 = 11; // Configuration already exists.
    const ECFG_NOT_INIT: u64 = 12; // Bridge not initialized;
    const ECFG_TOO_MUCH_RELAYERS: u64 = 13; // Too much relayers.
    const ECFG_PAUSED: u64 = 14; // Bridge paused.

    // Roles related.
    const EROLE_EXISTS: u64 = 100;  // Role already published.
    const EROLE_ADMIN: u64 = 101;   // Required admin role.
    const EROLD_RELAYER: u64 = 102; // Required relayer role.

    // Tokens related.
    const ETOKEN_CONFIG_EXISTS: u64 = 200; // Token config already exists.
    const ETOKEN_CONFIG_MISSED: u64 = 201; // Token config missed.

    // Deposits.
    const EDEPOSIT_WRONG_FEE: u64 = 300; // Wrong fee provided to deposit.

    // Proposals.
    const EPROPOSAL_EXISTS: u64 = 400;   // Proposal already exists.
    const EPROPOSAL_WRONG_CC: u64 = 401; // Wrong currency code.
    const EPROPOSAL_WRONG_CHAIN_ID: u64 = 402; // Wrong chain id.
    const EPROPOSAL_MISSED: u64 = 403; // Proposal missed.
    const EPROPOSAL_WRONG_ID: u64 = 404; // Wrong id.
    const EPROPOSAL_DOUBLE_VOTE: u64 = 404; // Double vote for proposal.
    const EPROPOSAL_WRONG_DATA: u64 = 405; // Wrong data when vote for proposal.

    // Initialization.
    // Initialize bridge.
    public fun initialize(account: &signer, chainId: u8, fee: u64, threshold: u64, deadline: u64) {
        let addr = Signer::address_of(account);
        assert(addr == DEPLOYER, Errors::custom(ECFG_NOT_DEPLOYER));

        // Check if configuration already exists.
        assert(!exists<Configuration>(addr), Errors::custom(ECFG_EXISTS));

        move_to(account, Configuration {
            admin: addr,
            chainId,
            fee,
            fees: Diem::zero<PONT>(),
            threshold,
            relayers: 0,
            paused: false,
            nonce: 0,
            deadline,
            deposit_events: Event::new_event_handle<DepositEvent>(account),
            relayers_status_events: Event::new_event_handle<RelayersStatusEvent>(account),
            config_events: Event::new_event_handle<ConfigEvent>(account),
            proposal_events: Event::new_event_handle<ProposalEvent>(account),
            vote_events: Event::new_event_handle<VoteEvent>(account),
            proposal_status_events: Event::new_event_handle<ProposalStatusEvent>(account),
        });

        grant_admin(account);
    }

    // Is bridge initialized?
    public fun is_initialized(): bool {
        exists<Configuration>(DEPLOYER)
    }

    // Throw error if bridge is not initialized.
    public fun assert_initialized() {
        assert(is_initialized(), Errors::custom(ECFG_NOT_INIT));
    }

    // Change fee.
    public fun change_fee(admin: &signer, new_fee: u64) acquires RoleId, Configuration {
        assert_admin(admin);
        let config = borrow_global_mut<Configuration>(DEPLOYER);
        config.fee = new_fee;

        Event::emit_event(
            &mut config.config_events,
            ConfigEvent {
                fee: config.fee,
                paused: config.paused,
                threshold: config.threshold,
            }
        );
    }

    // Get fee.
    public fun get_fee(): u64 acquires Configuration {
        borrow_global<Configuration>(DEPLOYER).fee
    }

    // Change threshold.
    public fun change_threshold(admin: &signer, new_threshold: u64) acquires RoleId, Configuration {
        assert_admin(admin);
        let config = borrow_global_mut<Configuration>(DEPLOYER);
        config.threshold = new_threshold;

        Event::emit_event(
            &mut config.config_events,
            ConfigEvent {
                fee: config.fee,
                paused: config.paused,
                threshold: config.threshold,
            }
        );
    }

    // Pause bridge.
    public fun pause(admin: &signer) acquires RoleId, Configuration {
        assert_admin(admin);
        let config = borrow_global_mut<Configuration>(DEPLOYER);
        config.paused = true;

        Event::emit_event(
            &mut config.config_events,
            ConfigEvent {
                fee: config.fee,
                paused: config.paused,
                threshold: config.threshold,
            }
        );
    }

    // Resume bridge.
    public fun resume(admin: &signer) acquires RoleId, Configuration {
        assert_admin(admin);
        let config = borrow_global_mut<Configuration>(DEPLOYER);
        config.paused = false;

        Event::emit_event(
            &mut config.config_events,
            ConfigEvent {
                fee: config.fee,
                paused: config.paused,
                threshold: config.threshold,
            }
        );
    }

    // Assert bridge paused.
    fun assert_paused() acquires Configuration {
        assert(!borrow_global<Configuration>(DEPLOYER).paused, Errors::custom(ECFG_PAUSED));
    }

    // Deposit and token related functions.
    // Deposit.
    public fun deposit<Token: store + drop>(chainId: u8, to_deposit: Diem<Token>, fee: Diem<PONT>, recipient: address, metadata: vector<u8>) acquires Configuration, TokenConfiguration {
        assert_initialized();
        assert_paused();

        let fees_value = Diem::value(&fee);

        // Wrong fee.
        assert(get_fee() == fees_value, Errors::custom(EDEPOSIT_WRONG_FEE));

        // Get configs.
        let config = borrow_global_mut<Configuration>(DEPLOYER);
        config.nonce = config.nonce + 1;

        let admin_addr = config.admin;

        // Token configuration doesn't exist.
        assert(exists<TokenConfiguration<Token>>(admin_addr), Errors::custom(ETOKEN_CONFIG_MISSED)); 

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
                chainId: chainId,
                nonce: config.nonce,
                amount: deposit_value,
                recipient,
                metadata,
                currency_code: Diem::currency_code<Token>(),
            }
        );
    }

    // Creating proposal, relayer choosed using standard off-chain round robin.
    // See README for better explanation.
    public fun create_proposal<Token: store + drop>(relayer: &signer, id: u128, chainId: u8, currency_code: vector<u8>, amount: u64, recipient: address, metadata: vector<u8>) acquires RoleId, Configuration {
        assert_initialized();
        assert_paused();
        assert_relayer(relayer);

        // Check if proposal already exists on account.
        assert(!exists<Proposal<Token>>(Signer::address_of(relayer)), Errors::custom(EPROPOSAL_EXISTS));

        // Check if currency code matches.
        assert(Diem::currency_code<Token>() == currency_code, Errors::custom(EPROPOSAL_WRONG_CC));

        let config = borrow_global<Configuration>(DEPLOYER);

        assert(config.chainId == chainId, Errors::custom(EPROPOSAL_WRONG_CHAIN_ID));

        let deadline = DiemBlock::get_current_block_height() + config.deadline;

        let proposal = Proposal<Token> {
            id,
            amount,
            recipient,
            metadata,
            deadline,
            votes_yes: Vector::empty(),
            votes_no: Vector::empty(),
        };
        move_to(relayer, proposal);
    }

    // Vote for proposal.
    public fun vote<Token: store + drop>(relayer: &signer, proposer: address, id: u128, yes: bool, data_hash: vector<u8>) : Option<Diem<Token>> acquires RoleId, Configuration, TokenConfiguration, Proposal {
        assert_initialized();
        assert_paused();
        assert_relayer(relayer);

        // Check proposal exists.
        assert(exists<Proposal<Token>>(proposer), Errors::custom(EPROPOSAL_MISSED));

        let config   = borrow_global<Configuration>(DEPLOYER);
        let proposal = borrow_global_mut<Proposal<Token>>(proposer);

        assert(proposal.id == id, Errors::custom(EPROPOSAL_WRONG_ID));

        let status = proposal_status(proposal, config);

        // Destroy proposal if it's rejected.
        if (status == PROPOSAL_STATUS_REJECTED) {
            move_from<Proposal<Token>>(proposer);
            return Option::none<Diem<Token>>()
        };

        // Match data_hash.
        let expected_hash: vector<u8> = Vector::empty();
        Vector::append(&mut expected_hash, BCS::to_bytes(&proposal.id));
        Vector::append(&mut expected_hash, BCS::to_bytes(&config.chainId));
        Vector::append(&mut expected_hash, BCS::to_bytes(&proposal.recipient));
        Vector::append(&mut expected_hash, BCS::to_bytes(&proposal.amount));
        Vector::append(&mut expected_hash, BCS::to_bytes(&proposal.metadata));  
        expected_hash = Hash::sha2_256(expected_hash);

        assert(expected_hash == data_hash, Errors::custom(EPROPOSAL_WRONG_DATA));  

        let relayer_addr = Signer::address_of(relayer);

        // Check double votes.
        assert(!Vector::contains(&proposal.votes_yes, &relayer_addr), Errors::custom(EPROPOSAL_DOUBLE_VOTE));
        assert(!Vector::contains(&proposal.votes_no,  &relayer_addr), Errors::custom(EPROPOSAL_DOUBLE_VOTE));

        if (yes) {
            Vector::push_back(&mut proposal.votes_yes, relayer_addr);

            let new_status = proposal_status(proposal, config);
            if (new_status == PROPOSAL_STATUS_PASSED) {
                let token_config = borrow_global_mut<TokenConfiguration<Token>>(config.admin);

                if (token_config.mintable) {
                    // TODO: we should mint new coins.
                    return Option::none<Diem<Token>>()
                } else {
                    let tokens = Diem::withdraw(&mut token_config.deposits, proposal.amount);

                    // TODO: we should deposit minted coins to user account using DiemAccount.
                    return Option::some(tokens)
                }
            };
        } else {
            Vector::push_back(&mut proposal.votes_no, relayer_addr);
            let new_status = proposal_status(proposal, config);

            // Destroy proposal.
            if (new_status == PROPOSAL_STATUS_REJECTED) {
                move_from<Proposal<Token>>(proposer);
            };
        };


        Option::none<Diem<Token>>()
    }

    // Remove porposal in case of deadline.
    public fun remove_proposal<Token: store + drop>(id: u128, proposer: address) acquires Configuration, Proposal {
        assert_initialized();

        assert(exists<Proposal<Token>>(proposer), Errors::custom(EPROPOSAL_MISSED));

        let proposal = borrow_global<Proposal<Token>>(proposer);

        assert(proposal.id == id, Errors::custom(EPROPOSAL_WRONG_ID));

        let config = borrow_global<Configuration>(DEPLOYER); 

        let status = proposal_status<Token>(proposal, config);

        if (status == PROPOSAL_STATUS_REJECTED) {
            move_from<Proposal<Token>>(proposer);
            return
        };

        abort 307 // Throw error as proposal not rejected yet 
    } 

    // Returns proposal status.
    fun proposal_status<Token: store + drop>(proposal: &Proposal<Token>, config: &Configuration): u64 {
        if (Vector::length(&proposal.votes_yes) >= config.threshold) {
            return PROPOSAL_STATUS_PASSED
        };

        if (Vector::length(&proposal.votes_no) >= config.threshold) {
            return PROPOSAL_STATUS_REJECTED
        };

        if (proposal.deadline > DiemBlock::get_current_block_height()) {
            return PROPOSAL_STATUS_REJECTED
        };

        PROPOSAL_STATUS_VOTING
    }

    // Add token configuration to admin.
    fun add_token_config<Token: store + drop>(admin: &signer, mintable: bool) acquires RoleId {
        assert_admin(admin);
        assert_initialized();

        assert(!exists<TokenConfiguration<Token>>(Signer::address_of(admin)), Errors::custom(ETOKEN_CONFIG_EXISTS));
        move_to(admin, TokenConfiguration<Token> {
            mintable,
            deposits: Diem::zero<Token>(),
            to_burn: Diem::zero<Token>(),
        });
    }

    // Change token configuration.
    fun change_token_mintable<Token: store + drop>(admin: &signer, mintable: bool) acquires RoleId, TokenConfiguration {
        assert_admin(admin);
        assert_initialized();

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
        assert(config.relayers + 1 != MAX_RELAYERS, Errors::custom(ECFG_TOO_MUCH_RELAYERS));
        config.relayers = config.relayers + 1;
        grant_relayer(relayer);

        Event::emit_event(
            &mut config.relayers_status_events,
            RelayersStatusEvent {
                account: Signer::address_of(relayer),
                status: RELAY_STATUS_ADDED,
                count: config.relayers,
            }
        );
    }

    // Revoke relayer.
    public fun revoke_relayer(admin: &signer, relayer: address) acquires RoleId, Configuration {
        assert_admin(admin);
        assert_initialized();

        drop_role(relayer);

        let config = borrow_global_mut<Configuration>(DEPLOYER);
        config.relayers = config.relayers - 1;

        Event::emit_event(
            &mut config.relayers_status_events,
            RelayersStatusEvent {
                account: relayer,
                status: RELAY_STATUS_REVOKED,
                count: config.relayers,
            }
        );
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
        assert(is_admin(account), Errors::custom(EROLE_ADMIN));
    }

    // Throw error if it's not relayer.
    fun assert_relayer(account: &signer) acquires RoleId {
        assert(is_relayer(account), Errors::custom(EROLD_RELAYER));
    }

    // Change admin account.
    public fun change_admin(admin: &signer, new_admin: &signer) acquires RoleId, Configuration {
        assert_admin(admin);
        assert_initialized();

        drop_role(Signer::address_of(admin));
        grant_admin(new_admin);
        borrow_global_mut<Configuration>(DEPLOYER).admin = Signer::address_of(new_admin);
    }

    // Move token configuration from old admin to new admin.
    public fun move_token_config<Token: store + drop>(admin: &signer, old_admin: address, mintable: bool) acquires RoleId, TokenConfiguration {
        assert_admin(admin);
        assert_initialized();

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

    // Withdraw fees.
    // TODO: split fees between relayers.
    public fun withdraw_fees(admin: &signer): Diem<PONT> acquires RoleId, Configuration {
        assert_admin(admin);
        assert_initialized();

        let conf = borrow_global_mut<Configuration>(DEPLOYER);
        let value = Diem::value(&conf.fees);
        Diem::withdraw(&mut conf.fees, value)
    }
}
}
