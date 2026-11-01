# Archive

`bash-v0.3/` is the Bash implementation of reqdrive, version 0.3, exactly as it stood when the
Rust rebuild began: its code, its tests, its documents, its CI workflow and its own older
`archive/` folder. Every path inside it is the path the file had at the repository root, so
every relative reference in its documents and tests still holds.

It is the reference for how things used to behave. It is not maintained, nothing in the Rust
workspace depends on it, and CI does not run it. Do not edit it.

## Do not use it to run an agent

The archived CLI is kept for reading, not for use. It has no security fixes, and its `launch`
command always runs the agent with `--unsafe` (`claude --dangerously-skip-permissions`), with no
way to turn that off: the agent gets unrestricted access to the machine. Its installer no longer
works either: `install.sh` is no longer at the repository root, and the script expects
`bin/reqdrive` there. Only run `archive/bash-v0.3/bin/reqdrive` directly, inside a throwaway
sandbox, if you need to compare old behaviour. Use the Rust `reqdrive story` command (see the
root README) for real work.

To run its suite (needs `bash`, `jq` and `sha256sum`; slow under Git Bash on Windows):

```bash
bash archive/bash-v0.3/tests/simple-test.sh
bash archive/bash-v0.3/tests/oracle-gate.sh
```
