script {
    use {{sender}}::Bridge;

    // Add relayer account to bridge.
    // Multisignature required.
    fun add_relayer(admin: signer, relayer: signer) {
        Bridge::add_relayer(&admin, &relayer);
    }
}
