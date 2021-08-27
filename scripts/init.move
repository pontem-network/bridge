script {
    use {{sender}}::Bridge;

    // Initialize bridge. 
    // Should be called from Bridge deployer address.
    // Configuration could be so:
    //  * chainId - 1.
    //  * fee - 10000000000.
    //  * threshold - 2 of 3 relayers.
    //  * deadline - 21600.
    fun init(admin: signer, chainId: u8, fee: u64, threshold: u64, deadline: u64) {
        Bridge::initialize(&admin, chainId, fee, threshold, deadline);
    }
}
