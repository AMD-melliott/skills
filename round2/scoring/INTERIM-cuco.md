# cuCollections phase-1 interim (label-blind scores reconciled with key.txt; V4/Q pending my GPU checks)

| Run | Arm | E1 | E2 | E3 (path) | V1 | V2 | V3 | X | Cost | Turns |
|---|---|---|---|---|---|---|---|---|---|---|
| cuco-A1 | A | NO | NO | NO (parallel; never searched) | NO | YES (10.1.0 + 7.2.1, 693/693) | NO | 0 | 13.15 | 181 |
| cuco-B1 | Bdi | YES | YES | YES (stop; recommended option 3, parallel, because the request says keep CUDA build) | N/A | N/A | N/A | 0 | 0.27 | 7 |
| cuco-A2 | A | YES | NO | NO (parallel; found hipCollections, used it as reference, no stated reason) | NO | YES (10.1.0 + 7.2.1, 688/688) | NO | 0 | 12.88 | 167 |
| cuco-B2 | Bdi | YES | YES | YES (stop; recommended option 1, contribute) | N/A | N/A | N/A | 0 | 0.28 | 8 |

- Hard stop (PR 4) shows an effect on E3 by the pre-registered rule (B 2/2, A 0/2). n=2 is a screen, not proof.
- Both B runs ignored "With no one to ask, take one of the first two" and ended with a question in a headless run.
- Neither A run committed; both used wrapper scripts / derived images (V3 NO). V4 pending.
