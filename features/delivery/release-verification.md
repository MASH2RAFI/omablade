This file was written by an agent.

# Verify release payloads

Verify a payload before installation or packaging. Its inventory binds file paths, modes, hashes, version, architecture, and source identity.

```sh
PAYLOAD/tools/native verify PAYLOAD
```

Demonstration: The valid candidate payload passes its actual inventory verification.

Tamper and mixed-version refusal paths are covered by the regression gate, not shown in this clip. Checksums are not publisher signatures.
