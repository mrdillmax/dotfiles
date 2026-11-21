# rustup is optional and no longer part of the default package set.
# Source its environment only when rustup created it.
if test -f "$HOME/.cargo/env.fish"
    source "$HOME/.cargo/env.fish"
end
