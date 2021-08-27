script {
    use {{sender}}::Bridge;
    use 0x1::PONT::PONT;
    use 0x1::Option;

    // Add PONT token to bridge.
    fun add_token_config(admin: signer) {
        Bridge::add_token_config<PONT>(&admin, false, Option::none(), Option::none());
    }
}
