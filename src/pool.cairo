#[starknet::interface]
trait IPool<ContractState> {
    fn last_wave(self: @ContractState) -> u64;
}

#[starknet::contract]
mod Pool {
    use starknet::ContractAddress;
    use super::IPool;

    #[storage]
    struct Storage {
        _last_wave: u64,
        _l1_controller: felt252
    }

    #[event]
    #[derive(starknet::Event, Drop)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, _l1_controller: felt252) {
        self._l1_controller.write(_l1_controller);
    }

    #[external(v0)]
    impl PoolImpl of IPool<ContractState> {
        fn last_wave(self: @ContractState) -> u64 {
            self._last_wave.read()
        }
    }

    #[l1_handler]
    fn return_wave(ref self: ContractState, from_address: felt252, sharePriceInU: u256) {
        assert(from_address == self._l1_controller.read(), 'Invalid sender');
        self._last_wave.write(starknet::get_block_timestamp());
    }
}
