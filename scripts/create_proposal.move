script {
    use {{sender}}::Bridge;
    use 0x1::PONT::PONT;

    // Create proposal.
    fun create_proposal(relayer: signer, id: u128, chainId: u8, currency_code: vector<u8>, amount: u64, recipient: address, metadata: vector<u8>) {
        Bridge::create_proposal<PONT>(&relayer, id, chainId, currency_code, amount, recipient, metadata);
    }
}
