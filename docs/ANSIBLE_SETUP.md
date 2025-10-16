# Ansible Setup in Packer Action

## Overview

The Packer Action automatically sets up Ansible and installs required Ansible Galaxy roles before running Packer builds. This is necessary because Packer templates in common-packer use Ansible provisioners that depend on community roles from Ansible Galaxy.

## What Gets Installed

### 1. Python and Ansible

- **Python 3.11**: Installed via `actions/setup-python@v5.6.0`
- **Ansible ~=9.2.0**: Matches the version used in common-packer

### 2. Ansible Galaxy Roles

The action automatically installs roles from two sources:

#### Common-Packer Roles (Required)

From `common-packer/requirements.yaml`:

```yaml
roles:
  - src: lfit.docker-install
  - src: lfit.haveged-install
  - src: lfit.java-install
  - src: lfit.lf-dev-libs
  - src: lfit.lf-recommended-tools
  - src: lfit.mono-install
  - src: lfit.packer-install
  - src: lfit.protobuf-install
  - src: lfit.puppet-install
  - src: lfit.python-install
  - src: lfit.shellcheck-install
  - src: lfit.sysstat-install
  - src: lfit.system-update
collections:
  - name: community.general
```

#### Project-Specific Roles (Optional)

If your project has a `requirements.yaml` file in the packer working directory, those roles will also be installed.

### 3. Installation Directory

Roles are installed to `.galaxy/` directory, which Packer can reference in its Ansible provisioner configuration.

## When It Runs

The Ansible setup runs in **both modes**:

- **Validate Mode**: Needed because Packer validation checks if Ansible provisioners can find their roles
- **Build Mode**: Required for actual provisioning during image builds

## How It Works

### Step-by-Step Process

1. **Setup Python** (All modes)

   ```yaml
   - name: Setup Python
     uses: actions/setup-python@v5.6.0
     with:
       python-version: "3.11"
   ```

2. **Install Ansible** (All modes)

   ```bash
   python -m pip install --upgrade pip
   pip install ansible~=9.2.0
   ```

3. **Install Galaxy Requirements** (All modes)
   ```bash
   # Auto-discover common-packer location
   if [[ -d "common-packer" ]]; then
     COMMON_PACKER_DIR="common-packer"
   elif [[ -d "packer/common-packer" ]]; then
     COMMON_PACKER_DIR="packer/common-packer"
   fi
   # Install common-packer requirements
   ansible-galaxy install -p .galaxy -r "$COMMON_PACKER_DIR/requirements.yaml"
   # Install project-specific requirements (if present)
   if [[ -f "requirements.yaml" ]]; then
     ansible-galaxy install -p .galaxy -r requirements.yaml
   fi
   ```

## Directory Structure

After setup, your workspace looks like:

```
workspace/
├── packer/
│   ├── common-packer/     # Submodule with core roles
│   │   └── requirements.yaml
│   ├── templates/
│   │   └── builder.pkr.hcl
│   └── vars/
│       └── ubuntu-22.04.pkrvars.hcl
└── .galaxy/               # Installed Ansible roles
    ├── lfit.docker-install/
    ├── lfit.java-install/
    └── ...
```

## Packer Template Usage

Your Packer templates can reference these roles:

```hcl
provisioner "ansible" {
  playbook_file = "${path.root}/../provision/baseline.yml"
  galaxy_file   = "${path.root}/../requirements.yaml"
  roles_path    = "${path.root}/../.galaxy"
}
```

## Troubleshooting

### Role Not Found Error

```
Error: failed to prepare provisioner-block "ansible"
FAILED! => {"msg": "the role 'lfit.docker-install' was not found"}
```

**Solution**: Ensure `common-packer` is checked out as a submodule:

```bash
git submodule update --init --recursive
```

### Requirements File Not Found

```
⚠️ Warning: common-packer directory not found. Skipping ansible-galaxy requirements.
```

**Solution**: The action expects one of these structures:

- `packer_working_dir/common-packer/requirements.yaml`
- `packer_working_dir/packer/common-packer/requirements.yaml`

Make sure `common-packer` is properly initialized.

### Wrong Ansible Version

If you need a different Ansible version, you'll need to fork the action and modify:

```yaml
pip install ansible~=<your-version>
```

Current version matches common-packer: `ansible~=9.2.0`

## Comparison with JJB Packer Builds

### Traditional JJB Approach

In Jenkins (from `~/git/builder/global-jjb/shell/`):

```bash
# Download lf-env.sh script
wget -q https://raw.githubusercontent.com/lfit/releng-global-jjb/master/jenkins-init-scripts/lf-env.sh
source ~/lf-env.sh

# Create virtual environment
lf-activate-venv --python python3.10 --venv-file "/tmp/.ansible_venv" ansible~=9.2.0

# Install roles
ansible-galaxy install -p .galaxy -r requirements.yaml
```

### GitHub Actions Approach

In this action (simplified):

```bash
# Python already available via actions/setup-python
python -m pip install ansible~=9.2.0

# No virtual environment needed (isolated runner)
ansible-galaxy install -p .galaxy -r requirements.yaml
```

**Key Differences**:

1. **No `lf-env.sh`**: GitHub runners already have Python pre-installed
2. **No virtual environment**: Each workflow run has an isolated environment
3. **Direct pip install**: Simpler, faster setup
4. **Auto-discovery**: Finds common-packer automatically

## References

- **Common-Packer**: `/home/abelur/git/lf-repos/common-packer/`
- **JJB Packer Build**: `~/git/builder/global-jjb/shell/packer-build.sh`
- **Ansible Galaxy Script**: `/home/abelur/git/lf-repos/common-packer/ansible-galaxy.sh`
- **Galaxy Requirements**: `/home/abelur/git/lf-repos/common-packer/requirements.yaml`

Signed-off-by: Anil Belur <askb23@gmail.com>
