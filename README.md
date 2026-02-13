# fzf :heart: kubectl

A kubectl wrapper with fzf interactive search. Falls back to plain kubectl when fzf isn't applicable.

[![demo]](https://github.com/user-attachments/assets/52417ed1-a265-421f-8e92-0a97296b636b)

## Install

```bash
# Command only
export PATH="$HOME/.bin/kfc:$PATH"

# Command + Ctrl+K widget
export PATH="$HOME/.bin/kfc:$PATH"
KFC_WIDGET=1 source "$HOME/.bin/kfc/k"
```

## Usage

```bash
k                    # Interactive browser
k get pods           # Browse pods
k ctx                # Switch context
k ns                 # Switch namespace
```

### Ctrl+K Widget (when enabled)

Press Ctrl+K to invoke kfc and append selection to command line:
- `kubectl logs ` + Ctrl+K → select pod
- `k get deploy ` + Ctrl+K → select deployment

### Keybindings

| Key      | Action          |
|----------|-----------------|
| `Ctrl+K` | Invoke widget   |
| `Ctrl+P` | Toggle preview  |
| `Ctrl+E` | Edit            |
| `Ctrl+Y` | View YAML       |
| `Ctrl+L` | Logs            |
| `Ctrl+F` | Port forward    |
| `Ctrl+S` | SSH/Scale       |
| `Ctrl+X` | Delete          |
| `Ctrl+T` | Switch type     |
| `Ctrl+N` | Switch namespace|
