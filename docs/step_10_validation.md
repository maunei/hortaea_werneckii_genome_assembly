## Step 10. Validation of a rerun

A rerun of the workflow is reproducible if it gives the same results within the variation the procedure itself shows. `validation/expected.tsv` lists the measures of the run reported here (written by `scripts/10_validate.py make-expected`) with an acceptance interval for each:

* the measures of Hw 2.1 (mean of the three polished runs): inside the range seen over the runs, widened on both sides by that range or by 0.5 percent of the mean, whichever is larger;
* the numbers of reads of the two PacBio sets: exact;
* the measures of Hw 2.0, which does not depend on any assembler: within 0.2 percent;
* the measures of the control assemblies (a single run each of programs whose results vary between computers): within 5 percent.

```bash
cd $HW
python3 scripts/10_validate.py check results     # after steps 04 to 09 have been rerun; give the results folder of the rerun
```

The report `results/10_validation/validation_report.txt` lists every item as `PASS`, `FAIL` or `MISSING` and ends with one line. When only some steps have been rerun, the items of the others are `MISSING`.
