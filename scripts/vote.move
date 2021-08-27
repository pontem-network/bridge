script {
    use {{sender}}::Bridge;
    use 0x1::PONT::PONT;
    use 0x1::Vector;
    use 0x1::BCS;
    use 0x1::Hash;

    // Vote for proposal.
    fun vote(relayer: signer, proposer: address, id: u128, yes: bool, chainId: u8, amount: u64, recipient: address, metadata: vector<u8>) {
        let hash: vector<u8> = Vector::empty();
        Vector::append(&mut hash, BCS::to_bytes(&id));
        Vector::append(&mut hash, BCS::to_bytes(&chainId));
        Vector::append(&mut hash, BCS::to_bytes(&recipient));
        Vector::append(&mut hash, BCS::to_bytes(&amount));
        Vector::append(&mut hash, BCS::to_bytes(&metadata));  
        hash = Hash::sha2_256(hash);

        Bridge::vote<PONT>(&relayer, proposer, id, yes, hash);
    }
}
