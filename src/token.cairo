use core::traits::Into;
use starknet::ContractAddress;


#[starknet::interface]
trait IERC20<ContractState> {
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
}

#[starknet::interface]
trait IGAToken<ContractState> {
    fn bridge_to_l1(ref self: ContractState, recipient: felt252, amount: u256) -> bool;
}

#[starknet::contract]
mod GAToken {
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use zeroable::Zeroable;
    use super::IGAToken;
    use starknet::syscalls::send_message_to_l1_syscall;
    use array::ArrayTrait;
    use traits::Into;

    #[storage]
    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _total_supply: u256,
        _balances: LegacyMap<ContractAddress, u256>,
        _allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        _l1_bridge: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        recipient: ContractAddress,
        _l1_bridge: felt252,
        owner: ContractAddress
    ) {
        initializer(ref self, name, symbol);
        _mint(ref self, recipient, initial_supply);
        self._l1_bridge.write(_l1_bridge);
    }

    #[external(v0)]
    impl ERC20 of super::IERC20<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self._name.read()
        }
        fn symbol(self: @ContractState) -> felt252 {
            self._symbol.read()
        }
        fn decimals(self: @ContractState) -> u8 {
            18_u8
        }
        fn total_supply(self: @ContractState) -> u256 {
            self._total_supply.read()
        }
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self._balances.read(account)
        }
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self._allowances.read((owner, spender))
        }
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            _transfer(ref self, sender, recipient, amount);
            true
        }
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            _spend_allowance(ref self, sender, caller, amount);
            _transfer(ref self, sender, recipient, amount);
            true
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            _approve(ref self, caller, spender, amount);
            true
        }
        fn totalSupply(self: @ContractState) -> u256 {
            self._total_supply.read()
        }
        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            ERC20::balance_of(self, account)
        }
        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            ERC20::transfer_from(ref self, sender, recipient, amount)
        }
        fn increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            _increase_allowance(ref self, spender, added_value)
        }
        fn increaseAllowance(
            ref self: ContractState, spender: ContractAddress, addedValue: u256
        ) -> bool {
            ERC20::increase_allowance(ref self, spender, addedValue)
        }
        fn decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            _decrease_allowance(ref self, spender, subtracted_value)
        }
        fn decreaseAllowance(
            ref self: ContractState, spender: ContractAddress, subtractedValue: u256
        ) -> bool {
            ERC20::decrease_allowance(ref self, spender, subtractedValue)
        }
    }

    /// @dev Internal Functions implementation for the GAToken contract
    #[external(v0)]
    impl GAToken of super::IGAToken<ContractState> {
        fn bridge_to_l1(ref self: ContractState, recipient: felt252, amount: u256) -> bool {
            _burn(ref self, get_caller_address(), amount);
            let mut calldata = ArrayTrait::new();
            calldata.append(recipient.into());
            calldata.append(amount.low.into());
            calldata.append(amount.high.into());
            send_message_to_l1_syscall(self._l1_bridge.read(), calldata.span()).unwrap_syscall();
            true
        }
    }

    /// @dev  L1 handler function that mints LP tokens for the recipient by transferring amount from the from_address on L1
    #[l1_handler]
    fn mint(
        ref self: ContractState, from_address: felt252, recipient: ContractAddress, amount: u256
    ) {
        assert(from_address == self._l1_bridge.read(), 'Invalid sender');
        _mint(ref self, recipient, amount);
    }


    //
    // Internals
    //

    #[internal]
    fn initializer(ref self: ContractState, name_: felt252, symbol_: felt252) {
        self._name.write(name_);
        self._symbol.write(symbol_);
    }

    #[internal]
    fn _increase_allowance(
        ref self: ContractState, spender: ContractAddress, added_value: u256
    ) -> bool {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self._allowances.read((caller, spender)) + added_value);
        true
    }

    #[internal]
    fn _decrease_allowance(
        ref self: ContractState, spender: ContractAddress, subtracted_value: u256
    ) -> bool {
        let caller = get_caller_address();
        _approve(
            ref self, caller, spender, self._allowances.read((caller, spender)) - subtracted_value
        );
        true
    }

    #[internal]
    fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        assert(!recipient.is_zero(), 'ERC20: mint to 0');
        self._total_supply.write(self._total_supply.read() + amount);
        self._balances.write(recipient, self._balances.read(recipient) + amount);
        self
            .emit(
                Event::Transfer(Transfer { from: Zeroable::zero(), to: recipient, value: amount })
            );
    }

    #[internal]
    fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
        assert(!account.is_zero(), 'ERC20: burn from 0');
        self._total_supply.write(self._total_supply.read() - amount);
        self._balances.write(account, self._balances.read(account) - amount);
        self.emit(Event::Transfer(Transfer { from: account, to: Zeroable::zero(), value: amount }));
    }

    #[internal]
    fn _approve(
        ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
    ) {
        assert(!owner.is_zero(), 'ERC20: approve from 0');
        assert(!spender.is_zero(), 'ERC20: approve to 0');
        self._allowances.write((owner, spender), amount);
        self.emit(Event::Approval(Approval { owner: owner, spender: spender, value: amount }))
    }

    #[internal]
    fn _transfer(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        self._balances.write(sender, self._balances.read(sender) - amount);
        self._balances.write(recipient, self._balances.read(recipient) + amount);
        self.emit(Event::Transfer(Transfer { from: sender, to: recipient, value: amount }));
    }

    #[internal]
    fn _spend_allowance(
        ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
    ) {
        let current_allowance = self._allowances.read((owner, spender));
        if current_allowance != BoundedInt::max() {
            _approve(ref self, owner, spender, current_allowance - amount);
        }
    }
}

