# Archive

`bash-v0.3/` is the Bash implementation of reqdrive, version 0.3, exactly as it stood when the
Rust rebuild began: its code, its tests, its documents, its CI workflow and its own older
`archive/` folder. Every path inside it is the path the file had at the repository root, so
every relative reference in its documents and tests still holds.

It is the reference for how things used to behave. It is not maintained, nothing in the Rust
workspace depends on it, and CI does not run it. Do not edit it.

To run its suite (needs `bash`, `jq` and `sha256sum`; slow under Git Bash on Windows):

```bash
bash archive/bash-v0.3/tests/simple-test.sh
bash archive/bash-v0.3/tests/oracle-gate.sh
```
