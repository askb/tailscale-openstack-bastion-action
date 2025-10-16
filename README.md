# OpenStack Bastion with Tailscale Action

A GitHub Action to setup and teardown OpenStack bastion hosts with Tailscale VPN for secure remote access. This action creates ephemeral bastion hosts that connect to your Tailscale network, enabling secure SSH access to OpenStack instances from GitHub Actions runners.

## Features

- 🔒 **Secure Access**: Uses Tailscale VPN for encrypted, zero-trust networking
- ☁️ **Cloud-Native**: Built for OpenStack cloud environments
- ⚡ **Ephemeral**: Automatic bastion creation and cleanup
- 🛡️ **Fail-Safe**: Automatic cleanup on timeout or failure
- 🔑 **Flexible Auth**: Supports both OAuth (recommended) and legacy auth keys
- 📊 **Detailed Logging**: Comprehensive logs for debugging

## Prerequisites

- OpenStack cloud account with necessary permissions
- Tailscale account with configured ACLs
- GitHub repository secrets configured (see Configuration section)

## Usage

### Basic Setup and Teardown

```yaml
jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      # Setup bastion
      - name: Setup bastion
        id: bastion
        uses: lfreleng-actions/openstack-bastion-action@v1
        with:
          operation: setup
          openstack_auth_url: ${{ secrets.OPENSTACK_AUTH_URL }}
          openstack_project_id: ${{ secrets.OPENSTACK_PROJECT_ID }}
          openstack_username: ${{ secrets.OPENSTACK_USERNAME }}
          openstack_password: ${{ secrets.OPENSTACK_PASSWORD }}
          tailscale_oauth_client_id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
          tailscale_oauth_secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
      
      # Use bastion
      - name: Use bastion for remote operations
        run: |
          echo "Bastion IP: ${{ steps.bastion.outputs.bastion_ip }}"
          # Your operations here
      
      # Always cleanup
      - name: Cleanup bastion
        if: always()
        uses: lfreleng-actions/openstack-bastion-action@v1
        with:
          operation: teardown
          bastion_name: ${{ steps.bastion.outputs.bastion_name }}
          openstack_auth_url: ${{ secrets.OPENSTACK_AUTH_URL }}
          openstack_project_id: ${{ secrets.OPENSTACK_PROJECT_ID }}
          openstack_username: ${{ secrets.OPENSTACK_USERNAME }}
          openstack_password: ${{ secrets.OPENSTACK_PASSWORD }}
```

### With Custom Configuration

```yaml
- name: Setup bastion with custom settings
  uses: lfreleng-actions/openstack-bastion-action@v1
  with:
    operation: setup
    bastion_flavor: v3-standard-4
    bastion_image: "Ubuntu 24.04 LTS"
    bastion_network: custom-network
    bastion_wait_timeout: 600
    tailscale_tags: tag:ci,tag:bastion
    debug_mode: true
    # ... OpenStack credentials
```

## Inputs

### Required Inputs

| Input | Description |
|-------|-------------|
| `operation` | Operation to perform: `setup` or `teardown` |
| `openstack_auth_url` | OpenStack authentication URL |
| `openstack_project_id` | OpenStack project/tenant ID |
| `openstack_username` | OpenStack username |
| `openstack_password` | OpenStack password (base64 encoded or plain) |

### Tailscale Authentication (for setup operation)

**Option 1: OAuth (Recommended)**
| Input | Description |
|-------|-------------|
| `tailscale_oauth_client_id` | Tailscale OAuth client ID |
| `tailscale_oauth_secret` | Tailscale OAuth client secret |

**Option 2: Auth Key (Legacy)**
| Input | Description |
|-------|-------------|
| `tailscale_auth_key` | Tailscale authentication key |

### Optional Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `openstack_region` | OpenStack region | `ca-ymq-1` |
| `openstack_network_id` | OpenStack network UUID | `` |
| `bastion_flavor` | Instance flavor | `v3-standard-2` |
| `bastion_image` | Base image name | `Ubuntu 22.04.5 LTS (x86_64) [2025-03-27]` |
| `bastion_network` | Network name | `odlci` |
| `bastion_ssh_key` | SSH key name | `` |
| `bastion_wait_timeout` | Timeout in seconds | `300` |
| `bastion_name` | Custom bastion name | `bastion-gh-{run_id}` |
| `tailscale_tags` | Tailscale tags | `tag:ci` |
| `tailscale_version` | Tailscale version | `latest` |
| `debug_mode` | Enable debug logging | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `bastion_ip` | Tailscale IP address of the bastion host |
| `bastion_name` | Name of the bastion instance |
| `status` | Operation status (`success` or `failure`) |

## Configuration

### GitHub Secrets

Configure these secrets in your GitHub repository:

#### Required Secrets
- `OPENSTACK_AUTH_URL`: OpenStack authentication endpoint
- `OPENSTACK_PROJECT_ID`: OpenStack project/tenant ID
- `OPENSTACK_USERNAME`: OpenStack username
- `OPENSTACK_PASSWORD` or `OPENSTACK_PASSWORD_B64`: OpenStack password (plain or base64 encoded)

#### Tailscale Secrets (choose one method)

**OAuth Method (Recommended)**
- `TAILSCALE_OAUTH_CLIENT_ID`: OAuth client ID
- `TAILSCALE_OAUTH_SECRET`: OAuth client secret

**Auth Key Method (Legacy)**
- `TAILSCALE_AUTH_KEY`: Authentication key

### Tailscale ACL Configuration

Your Tailscale ACL must include:

```json
{
  "tagOwners": {
    "tag:ci": ["autogroup:admin", "autogroup:owner", "tag:ci"],
    "tag:bastion": ["autogroup:admin", "autogroup:owner", "tag:ci", "tag:bastion"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:admin", "tag:ci", "tag:bastion"],
      "dst": ["*:*"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:member", "tag:ci"],
      "dst": ["tag:bastion"],
      "users": ["root", "ubuntu", "autogroup:nonroot"]
    }
  ]
}
```

See [Tailscale Setup Guide](docs/TAILSCALE_SETUP.md) for detailed configuration.

## How It Works

1. **Setup Operation**:
   - Connects GitHub Actions runner to Tailscale network
   - Creates cloud-init configuration with Tailscale setup
   - Launches OpenStack instance with cloud-init
   - Waits for bastion to join Tailscale network
   - Returns bastion Tailscale IP for secure access
   - Automatic cleanup if setup times out

2. **Teardown Operation**:
   - Deletes the OpenStack bastion instance
   - Verifies successful deletion

## Examples

See the [examples/workflows](examples/workflows/) directory for complete workflow examples.

## Development

See [DEVELOPMENT.md](docs/DEVELOPMENT.md) for development and testing guidelines.

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

## Support

For issues, questions, or contributions, please open an issue in the repository.
