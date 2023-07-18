use starknet::ContractAddress;

#[starknet::interface]
trait IPool<ContractState> {
    fn deposit(ref self: ContractState, amount: u256) -> bool;
    fn claim_lp(
        pending_withdraw: mapping<address, uint256>, lp_amount: u256, timestamp: u256
    ) -> bool;
    fn withdraw(ref self: ContractState, amount: u256) -> bool;
    fn claim_withdram(lp_amount: u256, timestamp: u256) -> bool;
    fn launch_wave() -> bool;
    fn wave_returned(amount: u256) -> bool;
}

#[starknet::contract]
mod Pool {
    use starknet;

    #[storage]
    struct Storage {
        _last_wave: timestamp,
        _amount: felt252,
        _pending_withdraw: mapping<address, uint256>,
        _pending_deposit: mapping<address, uint256>,
        _owner: ContractAddress,
    }

    #[event]
    #[derive(starknet::Event, Drop)]
    struct Event {
        Deposit: Deposit, 
    }

    #[constructor]
    fn constructor(
        _last_wave: timestamp,
        _amount: felt252,
        _pending_withdraw: mapping<address, uint256>,
        _pending_deposit: mapping<address, uint256>,
        _owner: ContractAddress,
    ) {
        initializer(ref self, amount);
    }

    #[external(v0)]
    impl PoolImpl of IPool<ContractState> {
        #[internal]
        fn initializer(ref self: ContractState, amount_: felt252) {
            self._amount.write(amount_);
            self.-owner.write()
        }

        fn deposit(ref self: ContractState, amount: u256) -> bool {
            assert(amount > 0, 'Amount must be greater than 0');
            self._amount += amount;
        }


        fn withdraw(amount: u256) -> bool {
            assert(amount <= self._amount, 'Amount must be greater than 0');
            self._amount -= amount;
        }
    }
}
