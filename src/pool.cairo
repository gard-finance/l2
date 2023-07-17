use starknet::ContractAddress;

#[starknet::interface]
trait IPool<ContractState> {}

#[starknet::contract]
mod Pool {
    use starknet;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(starknet::Event, Drop)]
    struct Event {}

    #[constructor]
    fn constructor(ref self: ContractAddress) {}

    #[external(v0)]
    impl PoolImpl of IPool<ContractState> {}
}
