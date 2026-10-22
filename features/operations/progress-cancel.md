This file was written by an agent.

# Track and cancel work

Long-running work returns an operation identifier. Inspect the operation or request cancellation; the result distinguishes cancelled and partial work.

```sh
omablade cancel-operation --yes
omablade operation OPERATION_ID
```

Demonstration: A real multi-file copy is cancelled and reports its cancelled result.

The operation-result response is consumed when fetched; a later repeated query may report an unknown identifier.
