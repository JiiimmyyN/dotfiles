### Usage

```bash
stow nvim
```

should create symlink `~/.config/nvim` -> `~/dotfiles/nvim/.config/nvim`


### Add new config

Assuming you are in root of repository

```bash
mkdir -p "nvim/.config"
mv ~/.config/nvim ~/dotfiles/nvim/.config/
stow nvim
```

replace nvim with given configuration, replace ~/dotfiles with location of repository
