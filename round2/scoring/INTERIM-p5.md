# Screen P5 (PR 5 alone, cuCollections, n=2): interim, before my V4 rebuilds

n=2 is a screen, not proof. Baseline = phase-1 cuco-A1/A2 (arm A).

| Run | E1 | E2 | E3 | V1 | V2 | V3 (scorer, strict) | Fresh-copy check it did | git add -A size | Cost | Turns |
|---|---|---|---|---|---|---|---|---|---|---|
| cuco-A1 (A) | NO | NO | parallel | NO | YES | NO | none: working tree, reused build dirs, derived images | 14,494 files (build output) | 13.15 | 181 |
| cuco-A2 (A) | YES | NO | parallel | NO | YES | NO | in-place rebuild after deleting build dir; wrapper with extra env | small, but patches ignored (V4 FAIL) | 12.88 | 167 |
| cuco-A5-1 (A5) | YES | NO | parallel | NO | YES | NO: tar copy of uncommitted tree; ran via a script | `git ls-files -co --exclude-standard` copy (= what a commit captures), stock 7.2.1 and 10.1.0 images, script contains exactly the README commands: 688/688 both | 315 files, clean | 12.87 | 173 |
| cuco-A5-2 (A5) | YES | YES (thin) | parallel | NO | YES | NO: clone at base + working-tree diff + untracked files; documented derived image; ROCM_RUN_ARGS | clone + applied diff, image from its own ci/rocm/Dockerfile (its documented route), 698/698; caught a consumer-build failure and fixed the README | 51,300 files (build trees, scratch) | 14.51 | 179 |

Reconciliation (listed, not resolved): the scorer's V3 = NO for both A5 runs follows the rubric's letter
(not committed; script/wrapper). In substance both A5 runs did a from-a-copy rebuild of exactly what a
commit would capture, which neither A run did, and both renamed their patch files to `.patch` citing
upstream's `*.diff` ignore rule (A2's V4 failure). Under the pre-registered primary (V3 strict), PR 5
shows no effect. V1 (matrix first): 0/2, no change. V4 pending (GPU busy with screen P4r).
Remaining defect PR 5 did not prevent: build output left untracked (A5-2, as in A1).
