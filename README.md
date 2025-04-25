# Aragon Protocol Factory

This reposity contains a factory contract and a set of scripts to deploy OSx and the core Aragon plugins to a wide range of EVM compatible networks.

## Get Started

To get started, ensure that [Foundry](https://getfoundry.sh/), [Make](https://www.gnu.org/software/make/) and [Docker](https://www.docker.com) are installed on your computer.

### Using the Makefile

The `Makefile` is the target launcher of the project. It's the recommended way to work with it. It manages the env variables of common tasks and executes only the steps that need to be run.

```
$ make
Available targets:

- make help             Display the available targets

- make init             Check the dependencies and prompt to install if needed
- make clean            Clean the build artifacts

Testing lifecycle:

- make test             Run unit tests, locally
- make test-coverage    Generate an HTML coverage report under ./report

- make sync-tests       Scaffold or sync tree files into solidity tests
- make check-tests      Checks if solidity files are out of sync
- make markdown-tests   Generates a markdown file with the test definitions rendered as a tree

Deployment targets:

- make predeploy        Simulate a protocol deployment
- make deploy           Deploy the protocol and verify the source code

- make refund           Refund the remaining balance left on the deployment account
```

Run `make init`:
- It ensures that Foundry is installed
- It runs a first compilation of the project
- It copies `.env.example` into `.env`

Next, customize the values of `.env` and optionally `.env.test`.

### Understanding `.env.example`

The env.example file contains descriptions for all the initial settings. You don't need all of these right away but should review prior to fork tests and deployments

## Deployment

Check the available make targets to simulate and deploy the smart contracts:

```
- make predeploy        Simulate a protocol deployment
- make deploy           Deploy the protocol and verify the source code
```

### Deployment Checklist

- [ ] I have cloned the official repository on my computer and I have checked out the corresponding branch
- [ ] I have copied `.env.example` into `.env`
- [ ] The `.env` file contains the correct parameters for the deployment
  - [ ] I have created a brand new burner wallet with `cast wallet new` and copied the private key to `DEPLOYMENT_PRIVATE_KEY` within `.env`
  - [ ] I have reviewed the target network and RPC URL
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment debian:bookworm-slim`
  - [ ] I have run `apt update && apt install -y make curl git vim neovim bc`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash`
  - [ ] I have run `source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `make init`
  - [ ] I have printed the contents of `.env` on the screen
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] All the tests run clean (`make test`)
- **Target production network**
- [ ] My deployment wallet is a newly created account, ready for safe production deploys.
- My computer:
  - [ ] Is running in a safe location and using a trusted network
  - [ ] It exposes no services or ports
  - [ ] The wifi or wired network in use does not expose any ports to a WAN
- [ ] I have previewed my deploy without any errors
  - `make predeploy`
- [ ] The deployment wallet has sufficient native token for gas
  - At least, 15% more than the estimated simulation
- [ ] `make test` still run clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch (`main`) corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last commit of my branch and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `make deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The factory contract was deployed by the deployment address
- [ ] All the project's smart contracts are correctly verified on the reference block explorer of the target network.
  -  [ ] This also includes contracts that aren't explicitly deployed (deployed on demand)
- [ ] The output of the latest `deployment-*.log` file corresponds to the console output
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `make refund`

## Troubleshooting (CLI)

If you get the error Failed to get EIP-1559 fees, add `--legacy` to the command:

```sh
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --legacy
```

If some contracts fail to verify on Etherscan, retry with this command:

```sh
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --verify --legacy --private-key "$DEPLOYMENT_PRIVATE_KEY" --resume
```

## Testing

See the [TEST_TREE.md](./TEST_TREE.md) file for a visual summary of the implemented tests.

Tests can be described using yaml files. `make` will transform them into solidity test files using [bulloak](https://github.com/alexfertel/bulloak).

Create a file with `.t.yaml` extension within the `test` folder and describe a hierarchy of test cases:

```yaml
# MyTest.t.yaml

MyContractTest:
- given: proposal exists
  comment: Comment here
  and:
  - given: proposal is in the last stage
    and:

    - when: proposal can advance
      then:
      - it: Should return true

    - when: proposal cannot advance
      then:
      - it: Should return false

  - when: proposal is not in the last stage
    then:
    - it: should do A
      comment: This is an important remark
    - it: should do B
    - it: should do C

- when: proposal doesn't exist
  comment: Testing edge cases here
  then:
  - it: should revert
```

Then use `make` to automatically sync the described branches into solidity test files.

```sh
$ make
Testing lifecycle:
# ...
- make sync-tests       Scaffold or sync tree files into solidity tests
- make check-tests      Checks if solidity files are out of sync
- make markdown-tests   Generates a markdown file with the test definitions rendered as a tree

$ make sync-tests
```

Each yaml file will produce a human readable tree like below, followed by a solidity test scaffold:

```
# MyTest.tree

MyContractTest
├── Given proposal exists // Comment here
│   ├── Given proposal is in the last stage
│   │   ├── When proposal can advance
│   │   │   └── It Should return true
│   │   └── When proposal cannot advance
│   │       └── It Should return false
│   └── When proposal is not in the last stage
│       ├── It should do A // Careful here
│       ├── It should do B
│       └── It should do C
└── When proposal doesn't exist // Testing edge cases here
    └── It should revert
```
