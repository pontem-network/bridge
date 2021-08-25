module Bridge {
    use 0x1::Signer;
    use 0x1::Errors;

    // Initial admin account address.
    const INITIAL_ADMIN: address = {{sender}};

    // Roles.

    // Resource contains role for specific account.
    struct RoleId has key {
        role_id: u8,
    }

    const ROLE_ADMIN: u8 = 1;
    const ROLE_RELAYER: u8 = 2;

    // Errors.
    const EROLE_EXISTS: u64 = 100; // Role already published.

    // Helper function to grant role.
    fun grant_role(account: &signer, role_id: u8) {
        assert(!exists<RoleId>(Signer::address_of(account)), Errors::custom(EROLE_EXISTS));
        move_to(account, RoleId { role_id });
    }
}
