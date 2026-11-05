# Tests of the workflow code

These tests check the scripts of the workflow without running the analysis: they need only Bash, Python 3 (standard library) and, for two of them, the
Python of the environment `04_probe`. They run in a few seconds and change nothing outside a temporary folder. When the variable `SLURM_TMPDIR` is set (inside a cluster job), `run_tests.sh` puts that folder on the local disk of the node: on a shared disk the many small files of the tests can be thousands of times slower and exceed the time limits of the tests (a command of a test may take up to 120 seconds; the limit only stops a test that hangs).

    bash tests/run_tests.sh            # all tests; prints PASS or FAIL for each
    bash tests/run_tests.sh t03        # the test t03 only (t03_settings.sh also works); fx03 runs the tests of that family; 03 runs both

| Test | What it checks |
|---|---|
| t01_syntax.sh | every shell script and job file passes `bash -n`, every Python script compiles |
| t02_submission.sh | with a mock `sbatch`: the dependencies of the jobs (for example Trinity waits for both RNA conversions, the screen of Hw 2.0 waits for the database index), a failed submission stops the script with an error, and a dry run leaves the ledger alone |
| t03_settings.sh | `settings.yaml` with an empty `modules:` followed by a comment and a quoted value reach `config/local.sh` unchanged; a folder name with a space, a quote, a backslash, a comma or `;` is refused with a message, never shortened |
| t04_fetch_archive.sh | the download never writes through a link to a shared source file, and leaves no half-written file under the final name |
| t05_step_errexit.sh | in the job of step 06 a command that fails in the middle of a step marks the step as failed |
| t06_collect_stale.sh | the result file of a step that failed is not used by the collection |
| t07_resources.sh | with a mock `sacct`, the table of resources counts the tasks of array jobs |
| t08_inputs_list.sh | the list of input checksums has no entry of the 18 git-lfs files and no duplicate |
| t09_archived_results.sh | optional: with `HW_TEST_RESULTS=<results folder of a complete run>` the summary step is run again on a copy and must give identical tables and verdicts |
| t10_screen_worker.sh | the worker of the database download receives its arguments in the right order (mock `curl`) |
| t12_array_coverage.sh | the number of accounting rows that the ledger requires (one per job, one per task of an array), and the final message job: it reports FAILED when a job has no row, an array has fewer rows than tasks, or a task did not complete |
| t13_inputs_missing.sh | the stage inputs counts the file deposited by the authors (not listed in `CHECKSUMS.md5` of older folders) as missing when it is absent |
| t14_resources_array_identity.sh | the table of resources requires exactly the tasks that the array of a job declares (ledger line or `#SBATCH --array` header of the job file) |
| t15_fetch_lock.sh | the downloader takes a lock on its destination folder: a second downloader of the same folder waits, one of another folder does not |

The files `fxNN_*.sh` (with `cases.py` and `support.py`, which must stay beside them) are regression tests of the failure paths: each one mocks the programs it needs (sbatch, sacct, curl, minimap2 and others), injects a failure, and checks that the failure is noticed, that a result that is correct still passes, and that the injected failure really happened. Several of them test the tests above (a deliberately broken copy of the code under test must make the test fail). The first lines of each file say what it checks. `t11_readme_dryrun.sh` compares the README with the output of the dry run.

The tests fx24 to fx34 (`cases_c.py` and `support_c.py` beside them) check the later fixes: unwritable or unrecordable ledger (fx24), temporary file of the preparation of Hw 2.0 (fx25), prerequisite of a step whose marker cannot be removed (fx26), error of the search in the table of databases (fx27), hard-linked marker and report of the downloader (fx28), the stage inputs with the deposited file missing (fx29), unfinished partial downloads and open file (fx30), steps that must run again (fx31), the deposited file and differing checksums in the check of the inputs (fx32), the downloads of step 07 and their jobs (fx33) and the filters of this runner (fx34).

The tests fx35 to fx58 (`cases_d.py`, `support_d.py`, `cases_e.py` and `support_e.py` beside them) check the remaining fixes of version 1.0.2: the folder lock of the downloader across the whole download and report update (fx35) and when the lock cannot be opened or taken (fx50, fx56), the check for queued jobs of an earlier ledger, the submission lock and a failing queue query (fx36, fx51, fx57), missing or empty manifests in the stage inputs (fx37), query errors in the database provenance table (fx38), errors in the awk and rename steps of the depth script (fx39, fx49), rerunning a dependent step when its prerequisite is newer even if the old marker cannot be removed (fx40), exact array task numbers and bracketed ranges in the resources table and final job (fx45, fx55), character checks of all keys and a relative `input_source` in `settings.yaml` (fx46), skipping lock, partial and report files when linking `input_source` (fx47), and folder locking and stale `.part` cleanup in the NCBI download of step 01 (fx48, fx52, fx58).
