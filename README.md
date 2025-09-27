# fzf :heart: kubectl

A minimal yet powerful kubectl wrapper that combines the functionality of kubectl with the interactive search capabilities of fzf. When fzf is not applicable (e.g., the results are not list-like), it gracefully falls back to the original kubectl command.

## :video_camera: Demo

[![demo]](https://github.com/user-attachments/assets/52417ed1-a265-421f-8e92-0a97296b636b)

## 🤔 Why

Because you can and you love fzf. - [@junegunn](http://github.com/junegunn/fzf?tab=readme-ov-file)

## 🚀 Features

- **Interactive Resource Selection**: Browse and select Kubernetes resources using fzf's fuzzy search
- **Context & Namespace Management**: Easily switch between contexts and namespaces
- **Quick Actions**: Perform common operations directly from the resource list
- **Live Preview**: Preview resource descriptions without leaving the interface
- **Multi-resource Support**: Works with all Kubernetes resource types

## 📋 Prerequisites

- `kubectl` - Kubernetes command-line tool
- `fzf` - Fuzzy finder for the command line
- `zsh` - Z shell (the script is written for zsh, didn't test in bash)

## 🛠️ Installation

1. Clone or download the `k` script
2. Make it executable:
   ```bash
   chmod +x k
   ```
3. Add it to your PATH or create a symlink:
   ```bash
   # Option 1: Add to PATH
   export PATH="/path/to/download:$PATH"
   
   # Option 2: Create symlink
   ln -s /path/to/download/k /usr/local/bin/k
   ```

## 🎯 Usage

### Basic Usage

```bash
# Interactive resource browser
k

# Context management
k ctx

# Namespace management  
k ns

# Get resources with fzf interface
k get pods
k get services
k get deployments

# Get resources from another context temporarily
k get pods --context=not-current-context

# Get resource from all namespaces
k get pods -A

# Fallback to the kubectl when fzf is not applicable for the results
k get pods nginx -o yaml
```

### Interactive Resource Browser

When you run `k` without arguments, it opens an interactive browser where you can:

1. **Select Resource Type**: Choose from all available Kubernetes resource types
2. **Browse Resources**: Use fuzzy search to find specific resources
3. **Perform Actions**: Use keyboard shortcuts for quick operations

### Keyboard Shortcuts

When browsing resources, use these keyboard shortcuts:

| Shortcut | Action | Description |
|----------|--------|-------------|
| `Ctrl+P` | Toggle Preview | Show/hide resource description preview |
| `Ctrl+I` | Describe | Open resource description in editor |
| `Ctrl+Y` | YAML View | Open resource YAML in editor |
| `Ctrl+E` | Edit | Edit the selected resource |
| `Ctrl+X` | Delete | Delete the selected resource (with confirmation) |
| `Ctrl+S` | Scale | Scale the selected resource |
| `Ctrl+L` | Logs | View logs for the selected resource |
| `Ctrl+F` | Port Forward | Set up port forwarding |
| `Ctrl+R` | Reload | Refresh the resource list |
| `Ctrl+U` | Preview Up | Scroll preview up |
| `Ctrl+D` | Preview Down | Scroll preview down |

### Context and Namespace Management

```bash
# Switch Kubernetes context
k ctx

# Switch namespace
k ns

# Use specific context and namespace
k --context=my-cluster --namespace=production get pods
```

### Advanced Usage

```bash
# Get all resources across namespaces
k get pods -A

# Use specific output format (bypasses fzf)
k get pods -o json

# Pass additional kubectl arguments
k get pods --field-selector=status.phase=Running
```

## 🔧 Configuration

The script automatically detects your current kubectl context and namespace. You can override these using command-line flags:

- `--context` or `--context=name`: Specify Kubernetes context
- `--namespace` or `-n`: Specify namespace
- `-A`: Show resources from all namespaces

## 📝 Examples

### Browse All Pods
```bash
k get pods
```

### Switch to Production Context
```bash
k ctx
# Select "production" from the list
```

### View Service Logs
```bash
k get services
# Select a service, then press Ctrl+L
```

### Scale a Deployment
```bash
k get deployments
# Select a deployment, then press Ctrl+S
# Enter the desired replica count
```

### Port Forward a Service
```bash
k get services
# Select a service, then press Ctrl+F
# Enter port mapping (e.g., 8080:80)
```

## 🎨 Interface

The interface provides:
- **Header**: Shows current context and namespace
- **Search**: Type to filter resources
- **Preview**: Right panel shows resource details
- **Status**: Inline info shows selection count

## 🚨 Error Handling

The script includes error handling for:
- Missing kubectl installation
- Missing fzf installation
- Invalid resource types
- Network connectivity issues

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and enhancement requests.

## 📄 License

This project is open source. Please check the license file for details.

## 🙏 Acknowledgments

- Inspired by the great work of [`pymag09/kubecui`](https://github.com/pymag09/kubecui)
- Built on top of the excellent `kubectl` tool
- Uses `fzf` for the interactive interface
- Inspired by the Kubernetes community's need for better CLI tools

---

**Note**: This tool is a wrapper around kubectl and requires proper Kubernetes cluster access and permissions to function correctly.
