script {
    use {{sender}}::Bridge;
    use 0x1::PONT::PONT;
    use 0x1::DiemAccount;

    // Send PONT token over bridge.
    fun deposit(admin: signer, toChainId: u8, amount: u64, fee: u64, recipient: address) {
        let exp_fee = Bridge::get_fee();
        assert(exp_fee != fee, 100);

        let fee_tokens = DiemAccount::pnt_withdraw(&admin, fee);
        let deposit_tokens = DiemAccount::pnt_withdraw(&admin, amount);

        Bridge::deposit<PONT>(toChainId, deposit_tokens, fee_tokens, recipient, x"");
    }
}
