use starknet::ContractAddress;

#[starknet::interface]
trait IGAToken<ContractState> {
    fn name(self: @ContractState) -> felt252;
    fn symbol(self: @ContractState) -> felt252;
    fn decimals(self: @ContractState) -> u8;
    fn total_supply(self: @ContractState) -> u256;
    fn balance_of(self: @ContractState, account: ContractAddress) -> u256;
    fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool;
    fn totalSupply(self: @ContractState) -> u256;
    fn balanceOf(self: @ContractState, account: ContractAddress) -> u256;
    fn transferFrom(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn increase_allowance(
        ref self: ContractState, spender: ContractAddress, added_value: u256
    ) -> bool;
    fn increaseAllowance(
        ref self: ContractState, spender: ContractAddress, addedValue: u256
    ) -> bool;
    fn decrease_allowance(
        ref self: ContractState, spender: ContractAddress, subtracted_value: u256
    ) -> bool;
    fn decreaseAllowance(
        ref self: ContractState, spender: ContractAddress, subtractedValue: u256
    ) -> bool;
    fn bridge_to_l1(ref self: ContractState, recipient: felt252, amount: u256) -> bool;
}

#[starknet::interface]
trait IPool<ContractState> {
    fn deposit(ref self: ContractState, amount: u256) -> bool;
    fn claim_lp(ref self: ContractState, lp_amount: u256) -> bool;
    fn withdraw(ref self: ContractState, amount: u256) -> bool;
    fn claim_withdram(ref self: ContractState, lp_amount: u256) -> bool;
    fn launch_wave(ref self: ContractState) -> bool;
    fn wave_returned(ref self: ContractState, amount: u256) -> bool;
}

#[starknet::contract]
mod Pool {
    use starknet;
    use super::IERC20DispatcherTrait;
    use super::IERC20Dispatcher;


    #[storage]
    struct Storage {
        _last_wave: u256,
        _amount: felt252,
        _pending_withdraw: mapping<address, uint256>,
        _pending_deposit: mapping<address, uint256>,
        _owner: ContractAddress,
    }

    #[event]
    #[derive(starknet::Event, Drop)]
    struct Event {
        Transfer: Transfer,
        Approval: Approval
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
        //transfer amount from caller to contractAddress
        }


        fn withdraw(amount: u256) -> bool {
            assert(amount <= self._amount, 'Amount must be greater than 0');
            self._amount -= amount;
        //burn Lp
        }

        fn claim_withdram(ref self: ContractState, lp_amount: u256, timestamp: u256) -> bool {
            self._amount -= lp_amount;
            let caller = get_caller_address();
            IERC20Dispatcher { contract_address: _contract_address }.transfer(caller, lp_amount)
        }
    }
}

