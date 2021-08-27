address {{sender}} {
    // Fake PONT coin.
    module XPONT {
        use 0x1::CoreAddresses;
        use 0x1::Diem;
        use 0x1::AccountLimits;
        use 0x1::FixedPoint32;

        struct XPONT has key, store {}

        /// Registers the `XUS` cointype. This can only be called from genesis.
        public fun initialize(
            dr_account: &signer,
        ): (Diem::MintCapability<XPONT>, Diem::BurnCapability<XPONT>) {
            // Operational constraint
            CoreAddresses::assert_currency_info(dr_account);

            let (mint_cap, burn_cap) = Diem::register_native_currency<XPONT>(
                dr_account,
                FixedPoint32::create_from_rational(1, 1), // exchange rate to PONT
                10000000000, // scaling_factor = 10^10
                10000000000, // fractional_part = 10^10
                b"XPONT",
                b"XPONT"
            );

            AccountLimits::publish_unrestricted_limits<XPONT>(dr_account);
            (mint_cap, burn_cap)
        }
    }

    module BridgeTests {
        use 0x1::AccountFreezing;
        use 0x1::ChainId;
        use 0x1::DualAttestation;
        use 0x1::Diem;
        use 0x1::DiemAccount;
        use 0x1::DiemBlock;
        use 0x1::DiemConfig;
        use 0x1::DiemSystem;
        use 0x1::DiemTimestamp;
        use 0x1::DiemVersion;
        use 0x1::TransactionFee;
        use 0x1::PONT::{Self, PONT};
        use 0x1::Signer;
        use 0x1::Option;
        use 0x1::Vector;
        use 0x1::Hash;
        use 0x1::BCS;
        use {{sender}}::XPONT::{Self, XPONT};
        use {{sender}}::Bridge;

        struct Drop has key {
            mint_cap: Diem::MintCapability<XPONT>,
            burn_cap: Diem::BurnCapability<XPONT>,
        }

        fun initialize(dr_account: &signer, tc_account: &signer, admin: &signer, chain_id: u8) {
            DiemAccount::initialize(dr_account, x"");
            ChainId::initialize(dr_account, chain_id);
            
            // On-chain config setup
            DiemConfig::initialize(dr_account);
            // Currency setup
            Diem::initialize(dr_account);
            // Currency setup
            PONT::initialize(dr_account, tc_account);
            AccountFreezing::initialize(dr_account);
            TransactionFee::initialize(tc_account);

            DiemSystem::initialize_validator_set(
                dr_account,
            );
            DiemVersion::initialize(
                dr_account,
            );
            DualAttestation::initialize(
                dr_account,
            );
            DiemBlock::initialize_block_metadata(dr_account);


            let (mint_cap, burn_cap) = XPONT::initialize(dr_account);

            DiemTimestamp::set_time_has_started(dr_account);

            DiemAccount::create_parent_vasp_account<XPONT>(tc_account, Signer::address_of(admin), x"", x"", true);
            DiemAccount::add_currency<PONT>(admin);

            let tokens = Diem::mint_with_capability<XPONT>(1000 * 10000000000, &mint_cap);
            move_to(dr_account, Drop {mint_cap, burn_cap});
            DiemAccount::pnt_deposit(Signer::address_of(admin), tokens);
        }

        #[test(
            dr = @0xA550C18,
            tr = @0xB1E55ED,
            admin = @5GcFHawZJHgwymsu9X2F5Lt5sSX89TxxFgHAMJ7TnoUJKqJD,
            relayer1 = @5FcJX8QjNKmXU7dST5UC2DK3wQkpaCzDmUEH2CYbaye2BzUZ,
            relayer2 = @5CwDi4jqXWV4WyAsNnW594PrVxVSBocmh8VwQfWiXaZWvdUd,
            relayer3  = @5G3fHKKuKHbNDR771aJkXroqRbbpSW84VbpDmgrNxHSu5RJ5,
        )]
        fun test_bridge(dr: &signer, tr: &signer, admin: &signer, relayer1: &signer, relayer2: &signer, relayer3: &signer) {
            let chain_id: u8 = 1;
            let fee: u64 = 0; // 1 PONT.
            let threshold: u64 = 2; // 2 relayers of 3.
            let deadline: u64 = 21600; // 3 days in blocks.
            let recipient = @5HmVTp81KU9P3DAzKVCJEwNPmqWr84UiFee56JYNbUreGcFg;
            let to_chain_id: u8 = 2;
            let amount: u64 = 100 * 10000000000;
            let proposal_id: u128 = 1;
            let metadata = x"";

            initialize(dr, tr, admin, chain_id);

            // Initialize bridge.
            Bridge::initialize(admin, chain_id, fee, threshold, deadline);
            Bridge::add_relayer(admin, relayer1);
            Bridge::add_relayer(admin, relayer2);
            Bridge::add_relayer(admin, relayer3);

            // Add XPONT config.
            Bridge::add_token_config<XPONT>(admin, false, Option::none(), Option::none());
        
            let fee_tokens = DiemAccount::pnt_withdraw<PONT>(admin, fee);
            let deposit_tokens = DiemAccount::pnt_withdraw<XPONT>(admin, amount);

            Bridge::deposit<XPONT>(to_chain_id, deposit_tokens, fee_tokens, recipient, x"");

            Bridge::create_proposal<XPONT>(relayer1, proposal_id, chain_id, Diem::currency_code<XPONT>(), amount, recipient, x"");

            let hash: vector<u8> = Vector::empty();
            Vector::append(&mut hash, BCS::to_bytes(&proposal_id));
            Vector::append(&mut hash, BCS::to_bytes(&chain_id));
            Vector::append(&mut hash, BCS::to_bytes(&recipient));
            Vector::append(&mut hash, BCS::to_bytes(&amount));
            Vector::append(&mut hash, BCS::to_bytes(&metadata));  
            hash = Hash::sha2_256(hash);

            Bridge::vote<XPONT>(relayer2, Signer::address_of(relayer1), proposal_id, true, copy hash);

            let new_balance = DiemAccount::balance<XPONT>(recipient);
            assert(new_balance == amount, 100);
        }
    }
}
