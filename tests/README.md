# Tests of the workflow code

These tests check the scripts of the workflow without running the analysis: they need only Bash, Python 3 (standard library) and, for two of them, the
Python of the environment `04_probe`. They run in a few seconds and change nothing outside a temporary folder.

    bash tests/run_tests.sh            # all tests; prints PASS or FAIL for each
    bash tests/run_tests.sh t03        # the tests whose name starts with t03

| Test | What it checks |
|---|---|
| t01_syntax.sh | every shell script and job file passes `bash -n`, every Python script compiles |
| t02_submission.sh | with a mock `sbatch`: the dependencies of the jobs (for example Trinity waits for both RNA conversions, the screen of Hw 2.0 waits for the database index), a failed submission stops the script with an error, and a dry run leaves the ledger alone |
| t03_settings.sh | `settings.yaml` with an empty `modules:` followed by a comment, and values with spaces and `$`, reach `config/local.sh` unchanged |
| t04_fetch_archive.sh | the download never writes through a link to a shared source file, and leaves no half-written file under the final name |
| t05_step_errexit.sh | in the job of step 06 a command that fails in the middle of a step marks the step as failed |
| t06_collect_stale.sh | the result file of a step that failed is not used by the collection |
| t07_resources.sh | with a mock `sacct`, the table of resources counts the tasks of array jobs |
| t08_inputs_list.sh | the list of input checksums has no entry of the 18 git-lfs files and no duplicate |
| t09_archived_results.sh | optional: with `HW_TEST_RESULTS=<results folder of a complete run>` the summary step is run again on a copy and must give identical tables and verdicts |
