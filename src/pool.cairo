/// @dev Core Library Imports for the Traits outside the Starknet Contract
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
    /// @dev Function that allows the contract owner to set the LP contract address, updating the state data, and returns true if the operation is successful
    fn set_lp(ref self: ContractState, lp: ContractAddress) -> bool;
    /// @dev Function that allows users to deposit funds into their account, updating the state data, and returns true if the deposit is successful
    fn deposit(ref self: ContractState, amount: u256) -> bool;
    /// @dev Function that allows users to claim LP tokens, updating the state data, and returns true if the claim is successful
    fn claim_lp(ref self: ContractState) -> bool;
    /// @dev Function that allows users to withdraw a specified amount of LP tokens, updating the state data, and returns true if the withdrawal is successful
    fn withdraw(ref self: ContractState, amount: u256) -> bool;
    /// @dev Function that allows users to claim LP tokens for their pending withdrawal, updating the state data, and returns true if the claim is successful
    fn claim_withdral(ref self: ContractState) -> bool;
    /// @dev Function that allows the contract owner to launch a new wave, updating the state data, and returns true if the wave is successfully launched
    fn launch_wave(ref self: ContractState) -> bool;
    /// @dev Function that returns the contract address of the LP associated with the contract state
    fn lp(self: @ContractState) -> ContractAddress;
    /// @dev Function that returns the contract address of the asset associated with the contract state
    fn asset(self: @ContractState) -> ContractAddress;
    /// @dev Function that returns the timestamp of the most recent wave stored in the contract state
    fn last_wave(self: @ContractState) -> u64;
    /// @dev Function that returns the value of the wave rate associated with the given wave_id from the contract state
    fn wave_rate(self: @ContractState, wave_id: felt252) -> u256;
    /// @dev Function that returns the total amount of pending deposits stored in the contract state
    fn total_pending_deposit_amount(self: @ContractState) -> u256;
    /// @dev Function that returns the total amount of pending withdrawals stored in the contract state
    fn total_pending_withdraw_amount(self: @ContractState) -> u256;
    /// @dev Function that returns the pending deposit details for the specified account from the contract state
    fn pending_deposit(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw;
    /// @dev Function that returns the pending withdrawal details for the specified account from the contract state
    fn pending_withdraw(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw;
    /// @dev Function that returns the contract address of the owner of the contract from the contract state
    fn owner(self: @ContractState) -> ContractAddress;
    /// @dev Function that returns a boolean value indicating whether a wave has been launched or not from the contract state
    fn wave_launched(self: @ContractState) -> bool;
    /// @dev Function that returns the value of the _l1_controller variable stored in the contract state, which is of type felt252
    fn l1_controller(self: @ContractState) -> felt252;
    /// @dev Function that returns the current wave ID from the contract state, which is of type `felt252`
    fn current_wave_id(self: @ContractState) -> felt252;
}

#[starknet::interface]
trait IMath<ContractState> {
    fn u256_unsafe_divmod(self: @ContractState, a: u256, b: u256) -> u256;
}

/// @dev Represents a DepositOrWithdraw with amout and wave_id value
#[derive(storage_access::StorageAccess, Drop, Copy, Serde)]
struct DepositOrWithdraw {
    amount: u256,
    wave_id: felt252
}

/// @dev Starknet contract facilitates deposits of amounts in the pool, enabling gas-efficient interaction with L1 networks
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
    use super::IMathDispatcher;
    use super::IMathDispatcherTrait;

    /// @dev Structure is designed to store the state data
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
        _l1_controller: felt252,
        _math: ContractAddress
    }

    /// @dev Event that gets emitted when a Deposit, Withdraw, LPClaimed or WithdrawalClaimed is cast
    #[event]
    #[derive(starknet::Event, Drop)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
        LPClaimed: LPClaimed,
        WithdrawalClaimed: WithdrawalClaimed
    }

    /// @dev Represents a Deposit that was cast
    #[derive(starknet::Event, Drop)]
    struct Deposit {
        account: ContractAddress,
        amount: u256
    }

    /// @dev Represents a Withdraw that was cast
    #[derive(starknet::Event, Drop)]
    struct Withdraw {
        account: ContractAddress,
        amount: u256
    }

    /// @dev Represents a LPClaimed that was cast
    #[derive(starknet::Event, Drop)]
    struct LPClaimed {
        account: ContractAddress,
        asset_amount: u256,
        wave_id: felt252,
        wave_rate: u256,
        lp_amount: u256,
    }

    /// @dev Represents a WithdrawalClaimed that was cast
    #[derive(starknet::Event, Drop)]
    struct WithdrawalClaimed {
        account: ContractAddress,
        lp_amount: u256,
        wave_id: felt252,
        wave_rate: u256,
        asset_amount: u256,
    }

    /// @dev Contract constructor initializing the contract with a contract address of asset, the owner of the contract and the controller of L1
    #[constructor]
    fn constructor(
        ref self: ContractState,
        asset: ContractAddress,
        owner: ContractAddress,
        l1_controller: felt252,
        math: ContractAddress
    ) {
        /// @dev initialise the data
        self._asset.write(asset);
        self._owner.write(owner);
        self._last_wave.write(get_block_timestamp());
        self._l1_controller.write(l1_controller);
        self._math.write(math);
    }

    /// @dev Implementation of IPool for ContractState
    #[external(v0)]
    impl PoolImpl of IPool<ContractState> {
        /// @dev Deposit function that transfers tokens from the caller to the contract, updates the contract's state, and returns true if the deposit is successful
        fn deposit(ref self: ContractState, amount: u256) -> bool {
            IERC20Dispatcher {
                contract_address: self._asset.read()
            }.transferFrom(get_caller_address(), get_contract_address(), amount);
            add_deposit_to_total(ref self, amount);
            add_pending_deposit(ref self, get_caller_address(), amount);
            true
        }

        /// @dev Allows the caller to claim LP tokens by minting an amount based on their pending deposit's wave_id and resets the deposit state
        fn claim_lp(ref self: ContractState) -> bool {
            let deposit = self._pending_deposit.read(get_caller_address());
            assert(self._current_wave_id.read() != deposit.wave_id, 'Wait next wave to claim');
            reset_pending_deposit(ref self, get_caller_address());
            let wave_rate = self._wave_rate.read(deposit.wave_id);
            IGALPDispatcher {
                contract_address: self._lp.read()
            }
                .mint(
                    get_caller_address(),
                    IMathDispatcher {
                        contract_address: self._math.read()
                    }.u256_unsafe_divmod(deposit.amount, wave_rate)
                )
        }

        /// @dev Allows the caller to withdraw a specified amount of LP tokens by burning them, updates the contract's internal state for the withdrawal, and returns true if the withdrawal is successful
        fn withdraw(ref self: ContractState, amount: u256) -> bool {
            IGALPDispatcher {
                contract_address: self._lp.read()
            }.burn(get_caller_address(), amount);
            add_withdraw_to_total(ref self, amount);
            add_pending_withdraw(ref self, get_caller_address(), amount);
            true
        }

        /// @dev This function allows the caller to claim LP tokens for their pending withdrawal based on the wave_id, resets the withdrawal state, and transfers the calculated amount to the caller

        fn claim_withdral(ref self: ContractState) -> bool {
            let withdraw = self._pending_withdraw.read(get_caller_address());
            assert(self._current_wave_id.read() != withdraw.wave_id, 'Wait next wave to claim');
            reset_pending_withdraw(ref self, get_caller_address());
            let wave_rate = self._wave_rate.read(withdraw.wave_id);
            IERC20Dispatcher {
                contract_address: self._asset.read()
            }.transfer(get_caller_address(), withdraw.amount * wave_rate)
        }

        /// @dev Enables the contract owner to launch a new wave with specific conditions, including blocking multiple waves within 24 hours, sending information to L1, and resetting pending amounts
        fn launch_wave(ref self: ContractState) -> bool {
            assert(get_caller_address() == self._owner.read(), 'Only owner');
            assert(self._wave_launched.read() == false, 'Wave already launched');
            // assert(self._last_wave.read() + 24 * 3600 < get_block_timestamp(), 'Wave is every 24h');
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

        /// @dev Allows the contract owner to set the LP contract address, updating the state data, and returns true if the operation is successful
        fn set_lp(ref self: ContractState, lp: ContractAddress) -> bool {
            assert(self._owner.read() == get_caller_address(), 'Only owner');
            self._lp.write(lp);
            true
        }

        /// @dev Returns the contract address of the LP associated with the contract state
        fn lp(self: @ContractState) -> ContractAddress {
            self._lp.read()
        }

        /// @dev Returns the contract address of the asset associated with the contract state
        fn asset(self: @ContractState) -> ContractAddress {
            self._asset.read()
        }

        /// @dev Returns the value of the last_wave variable stored in the contract state, representing the timestamp of the most recent wave
        fn last_wave(self: @ContractState) -> u64 {
            self._last_wave.read()
        }

        /// @dev Returns the value of the _current_wave_id variable stored in the contract state, which is of type felt252
        fn current_wave_id(self: @ContractState) -> felt252 {
            self._current_wave_id.read()
        }

        /// @dev Returns the wave rate value associated with the given wave_id, which is of type felt252, from the contract state, the wave rate is of type u256
        fn wave_rate(self: @ContractState, wave_id: felt252) -> u256 {
            self._wave_rate.read(wave_id)
        }

        /// @dev Returns the value of the _total_pending_deposit_amount variable stored in the contract state, which represents the total amount of pending deposits. The amount is of type u256
        fn total_pending_deposit_amount(self: @ContractState) -> u256 {
            self._total_pending_deposit_amount.read()
        }


        /// @dev Returns the value of the _total_pending_withdraw_amount variable stored in the contract state, which represents the total amount of pending withdrawals. The amount is of type u256
        fn total_pending_withdraw_amount(self: @ContractState) -> u256 {
            self._total_pending_withdraw_amount.read()
        }

        /// @dev Returns the value of the _pending_deposit variable associated with the specified account, which is of type ContractAddress, from the contract state. The return type is DepositOrWithdraw, representing the pending deposit details for the specified account
        fn pending_deposit(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw {
            self._pending_deposit.read(account)
        }

        /// @dev Returns the value of the _pending_withdraw variable associated with the specified account, which is of type ContractAddress, from the contract state. The return type is DepositOrWithdraw, representing the pending withdrawal details for the specified account
        fn pending_withdraw(self: @ContractState, account: ContractAddress) -> DepositOrWithdraw {
            self._pending_withdraw.read(account)
        }

        /// @dev Returns the contract address of the owner of the contract.
        fn owner(self: @ContractState) -> ContractAddress {
            self._owner.read()
        }

        /// @dev Returns a boolean value representing if wave has been launched or not.
        fn wave_launched(self: @ContractState) -> bool {
            self._wave_launched.read()
        }

        /// @dev Returns the value of the _l1_controller variable stored in the contract state, which is of type felt252. The variable represents the controller contract address associated with the Layer 1 system
        fn l1_controller(self: @ContractState) -> felt252 {
            self._l1_controller.read()
        }
    }

    /// @dev This L1 handler function processes external system return data related to a wave, updating the contract state with wave information like the wave rate, current wave ID, and setting the wave launched status to false
    #[l1_handler]
    fn handle_wave_return(ref self: ContractState, from_address: felt252, wave_rate: u256) {
        assert(from_address == self._l1_controller.read(), 'Only controller');
        self._wave_launched.write(false);
        let wave_id = self._current_wave_id.read();
        self._wave_rate.write(wave_id, wave_rate);
        self._current_wave_id.write(wave_id);
    }

    // INTERNALS
    /// @dev Increments the total pending deposit amount stored in the contract state by the given amount.
    fn add_deposit_to_total(ref self: ContractState, amount: u256) {
        self
            ._total_pending_deposit_amount
            .write(self._total_pending_deposit_amount.read() + amount);
    }

    /// @dev adds a pending deposit entry for the specified account with the given amount, but it asserts that the account has not made a previous deposit (amount == 0) or claimed LPs (wave_id == 0) before adding the new pending deposit. The function sets the new pending deposit with the provided amount and the current wave ID from the contract state
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

    /// @dev Resets the pending deposit entry for the specified account to zero amount and zero wave_id in the contract state.
    fn reset_pending_deposit(ref self: ContractState, account: ContractAddress) {
        self._pending_deposit.write(account, DepositOrWithdraw { amount: 0, wave_id: 0 });
    }

    /// @dev Increments the total pending withdraw amount stored in the contract state by the given amount.
    fn add_withdraw_to_total(ref self: ContractState, amount: u256) {
        self
            ._total_pending_withdraw_amount
            .write(self._total_pending_withdraw_amount.read() + amount);
    }

    /// @dev Adds a pending withdrawal entry for the specified account with the given amount, but it asserts that the account has not made a previous withdrawal (amount == 0) or claimed assets (wave_id == 0) before adding the new pending withdrawal. The function sets the new pending withdrawal with the provided amount and the current wave ID from the contract state
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

    /// @dev Resets the pending withdrawal entry for the specified account to zero amount and zero wave_id in the contract state
    fn reset_pending_withdraw(ref self: ContractState, account: ContractAddress) {
        self._pending_withdraw.write(account, DepositOrWithdraw { amount: 0, wave_id: 0 });
    }

    /// @dev Blocks the launching of the next wave by updating the contract state. It sets _wave_launched to true, indicating that the next wave has been blocked, and _last_wave to the current block timestamp to mark the time when the wave was blocked
    fn block_next_wave(ref self: ContractState) {
        self._wave_launched.write(true);
        self._last_wave.write(get_block_timestamp());
    }

    /// @dev Resets the total pending deposit and withdrawal amounts in the contract state to zero. It sets _total_pending_deposit_amount and _total_pending_withdraw_amount to 0
    fn reset_amounts(ref self: ContractState) {
        self._total_pending_deposit_amount.write(0);
        self._total_pending_withdraw_amount.write(0);
    }
}

