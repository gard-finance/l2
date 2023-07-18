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
    // externals
    fn deposit(ref self: ContractState, amount: u256) -> bool;
    fn claim_lp(ref self: ContractState) -> bool;
    fn withdraw(ref self: ContractState, amount: u256) -> bool;
    fn claim_withdral(ref self: ContractState) -> bool;
    fn launch_wave(ref self: ContractState) -> bool;
    fn set_lp(ref self: ContractState, lp: ContractAddress) -> bool;
    // views 
    fn lp(self: @ContractState) -> ContractAddress;
    fn asset(self: @ContractState) -> ContractAddress;
    fn last_wave(self: @ContractState) -> u64;
    fn current_wave_id(self: @ContractState) -> felt252;
    fn wave_rate(self: @ContractState, wave_id: felt252) -> u256;
    fn total_pending_deposit_amount(self: @ContractState) -> u256;
    fn total_pending_withdraw_amount(self: @ContractState) -> u256;
    fn pending_deposit(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw;
    fn pending_withdraw(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw;
    fn owner(self: @ContractState) -> ContractAddress;
    fn wave_launched(self: @ContractState) -> bool;
    fn l1_controller(self: @ContractState) -> felt252;
}

#[derive(storage_access::StorageAccess, Drop, Copy, Serde)]
struct DepositOrWithdraw {
    amount: u256,
    wave_id: felt252
}

#[starknet::contract]
mod Pool {
    use starknet::ContractAddress;
    use starknet::get_contract_address;
    use starknet::get_caller_address;
    use starknet::get_block_timestamp;
    use super::IPool;
    use l2::token::IGATokenDispatcher;
    use l2::token::IGATokenDispatcherTrait;
    use l2::token::IERC20Dispatcher;
    use l2::token::IERC20DispatcherTrait;
    use l2::lp::IGALPDispatcher;
    use l2::lp::IGALPDispatcherTrait;
    use starknet::syscalls::send_message_to_l1_syscall;
    use array::ArrayTrait;
    use traits::Into;
    use super::DepositOrWithdraw;

    #[storage]
    struct Storage {
        _wave_launched: bool,
        _last_wave: u64,
        _current_wave_id: felt252,
        _wave_rate: LegacyMap<felt252, u256>,
        _lp: ContractAddress,
        _asset: ContractAddress,
        _total_pending_deposit_amount: u256,
        _total_pending_withdraw_amount: u256,
        _pending_deposit: LegacyMap<ContractAddress, DepositOrWithdraw>,
        _pending_withdraw: LegacyMap<ContractAddress, DepositOrWithdraw>,
        _owner: ContractAddress,
        _l1_controller: felt252
    }

    #[event]
    #[derive(starknet::Event, Drop)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
        LPClaimed: LPClaimed,
        WithdrawalClaimed: WithdrawalClaimed
    }

    #[derive(starknet::Event, Drop)]
    struct Deposit {
        account: ContractAddress,
        amount: u256
    }

    #[derive(starknet::Event, Drop)]
    struct Withdraw {
        account: ContractAddress,
        amount: u256
    }

    #[derive(starknet::Event, Drop)]
    struct LPClaimed {
        account: ContractAddress,
        asset_amount: u256,
        wave_id: felt252,
        wave_rate: u256,
        lp_amount: u256,
    }

    #[derive(starknet::Event, Drop)]
    struct WithdrawalClaimed {
        account: ContractAddress,
        lp_amount: u256,
        wave_id: felt252,
        wave_rate: u256,
        asset_amount: u256,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        asset: ContractAddress,
        owner: ContractAddress,
        l1_controller: felt252
    ) {
        self._asset.write(asset);
        self._owner.write(get_caller_address());
        self._last_wave.write(get_block_timestamp());
        self._l1_controller.write(l1_controller);
    }

    #[external(v0)]
    impl PoolImpl of IPool<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) -> bool {
            IERC20Dispatcher {
                contract_address: self._asset.read()
            }.transferFrom(get_caller_address(), get_contract_address(), amount);
            add_deposit_to_total(ref self, amount);
            add_pending_deposit(ref self, get_caller_address(), amount);
            true
        }

        fn claim_lp(ref self: ContractState) -> bool {
            let deposit = self._pending_deposit.read(get_caller_address());
            assert(self._current_wave_id.read() != deposit.wave_id, 'Wait next wave to claim');
            reset_pending_deposit(ref self, get_caller_address());
            let wave_rate = self._wave_rate.read(deposit.wave_id);
            IGALPDispatcher {
                contract_address: self._lp.read()
            }.mint(get_caller_address(), deposit.amount / wave_rate)
        }

        fn withdraw(ref self: ContractState, amount: u256) -> bool {
            IGALPDispatcher {
                contract_address: self._asset.read()
            }.burn(get_caller_address(), amount);
            add_withdraw_to_total(ref self, amount);
            add_pending_withdraw(ref self, get_caller_address(), amount);
            true
        }

        fn claim_withdral(ref self: ContractState) -> bool {
            let withdraw = self._pending_withdraw.read(get_caller_address());
            assert(self._current_wave_id.read() != withdraw.wave_id, 'Wait next wave to claim');
            reset_pending_withdraw(ref self, get_caller_address());
            let wave_rate = self._wave_rate.read(withdraw.wave_id);
            IERC20Dispatcher {
                contract_address: self._asset.read()
            }.transfer(get_caller_address(), withdraw.amount * wave_rate)
        }

        fn launch_wave(ref self: ContractState) -> bool {
            assert(get_caller_address() == self._owner.read(), 'Only owner');
            assert(self._wave_launched.read() == false, 'Wave already launched');
            assert(self._last_wave.read() + 24 * 3600 < get_block_timestamp(), 'Wave is every 24h');
            block_next_wave(ref self);
            let mut payload = ArrayTrait::new();
            let deposit_amount = self._total_pending_deposit_amount.read();
            let withdraw_amount = self._total_pending_withdraw_amount.read();
            if (deposit_amount > withdraw_amount) {
                payload.append(0);
                payload.append((deposit_amount - withdraw_amount).low.into());
                payload.append((deposit_amount - withdraw_amount).high.into());
            } else if (deposit_amount < withdraw_amount) {
                payload.append(1);
                payload.append((withdraw_amount - deposit_amount).low.into());
                payload.append((withdraw_amount - deposit_amount).high.into());
            } else {
                assert(false == true, 'Useless wave');
            }
            reset_amounts(ref self);
            send_message_to_l1_syscall(self._l1_controller.read(), payload.span()).unwrap_syscall();
            true
        }

        fn set_lp(ref self: ContractState, lp: ContractAddress) -> bool {
            assert(self._owner.read() == get_caller_address(), 'Only owner');
            self._lp.write(lp);
            true
        }

        fn lp(self: @ContractState) -> ContractAddress {
            self._lp.read()
        }
        fn asset(self: @ContractState) -> ContractAddress {
            self._asset.read()
        }
        fn last_wave(self: @ContractState) -> u64 {
            self._last_wave.read()
        }
        fn current_wave_id(self: @ContractState) -> felt252 {
            self._current_wave_id.read()
        }
        fn wave_rate(self: @ContractState, wave_id: felt252) -> u256 {
            self._wave_rate.read(wave_id)
        }
        fn total_pending_deposit_amount(self: @ContractState) -> u256 {
            self._total_pending_deposit_amount.read()
        }
        fn total_pending_withdraw_amount(self: @ContractState) -> u256 {
            self._total_pending_withdraw_amount.read()
        }
        fn pending_deposit(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw {
            self._pending_deposit.read(account)
        }
        fn pending_withdraw(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw {
            self._pending_withdraw.read(account)
        }
        fn owner(self: @ContractState) -> ContractAddress {
            self._owner.read()
        }
        fn wave_launched(self: @ContractState) -> bool {
            self._wave_launched.read()
        }
        fn l1_controller(self: @ContractState) -> felt252 {
            self._l1_controller.read()
        }
    }

    #[l1_handler]
    fn handle_wave_return(ref self: ContractState, from_address: felt252, wave_rate: u256) {
        assert(from_address == self._l1_controller.read(), 'Only controller');
        self._wave_launched.write(false);
        let wave_id = self._current_wave_id.read();
        self._wave_rate.write(wave_id, wave_rate);
        self._current_wave_id.write(wave_id);
    }

    // INTERNALS

    fn add_deposit_to_total(ref self: ContractState, amount: u256) {
        self
            ._total_pending_deposit_amount
            .write(self._total_pending_deposit_amount.read() + amount);
    }

    fn add_pending_deposit(ref self: ContractState, account: ContractAddress, amount: u256) {
        let deposit = self._pending_deposit.read(account);
        assert(deposit.amount == 0, 'claim LPs before depositing');
        assert(deposit.wave_id == 0, 'claim LPs before depositing');
        self
            ._pending_deposit
            .write(
                account, DepositOrWithdraw { amount: amount, wave_id: self._current_wave_id.read() }
            )
    }

    fn reset_pending_deposit(ref self: ContractState, account: ContractAddress) {
        self._pending_deposit.write(account, DepositOrWithdraw { amount: 0, wave_id: 0 });
    }

    fn add_withdraw_to_total(ref self: ContractState, amount: u256) {
        self
            ._total_pending_withdraw_amount
            .write(self._total_pending_withdraw_amount.read() + amount);
    }

    fn add_pending_withdraw(ref self: ContractState, account: ContractAddress, amount: u256) {
        let withdraw = self._pending_withdraw.read(account);
        assert(withdraw.amount == 0, 'claim assets before withdrawing');
        assert(withdraw.wave_id == 0, 'claim assets before withdrawing');
        self
            ._pending_withdraw
            .write(
                account, DepositOrWithdraw { amount: amount, wave_id: self._current_wave_id.read() }
            )
    }

    fn reset_pending_withdraw(ref self: ContractState, account: ContractAddress) {
        self._pending_withdraw.write(account, DepositOrWithdraw { amount: 0, wave_id: 0 });
    }

    fn block_next_wave(ref self: ContractState) {
        self._wave_launched.write(true);
        self._last_wave.write(get_block_timestamp());
    }

    fn reset_amounts(ref self: ContractState) {
        self._total_pending_deposit_amount.write(0);
        self._total_pending_withdraw_amount.write(0);
    }
}

