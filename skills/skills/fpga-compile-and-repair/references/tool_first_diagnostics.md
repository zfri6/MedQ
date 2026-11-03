# Tool-First Diagnostics

## Evidence To Preserve

- exact command
- working directory
- tool path and version if available
- stdout/stderr
- file list and include dirs
- macros/defines

## Classification

| Class | Examples | Preferred action |
| --- | --- | --- |
| Syntax | missing semicolon, malformed port | minimal local edit |
| Name binding | undeclared signal, missing package | read nearby code and add/import correct declaration |
| Interface | port mismatch, width mismatch | compare contract and instantiation |
| Elaboration | parameter issue, generate issue | inspect parameter values and conditional branches |
| Simulation-only | delay/event in RTL path | move to TB or guard with synthesis directive if appropriate |
| Environment | missing include/IP/library | fix command or ask for dependency |
